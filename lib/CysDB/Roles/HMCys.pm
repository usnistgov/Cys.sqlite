package CysDB::Roles::HMCys;

# ABSTRACT: pull out Cysteine disulfide info from pdb
use Moose::Role;
use HackaMol;
use Math::Vector::Real;
use Math::Vector::Real::Neighbors;
use Math::Vector::Real::kdTree;

use Scalar::Util qw(refaddr);
use Data::Dumper;

#global builder
my $bldr = HackaMol->new();

sub cys_groups {

    # return list of groups for the cys table
    # return chain_cys table info: entity_id, asym_id (chain), auth_asym_id
    #     chains_cys.res_count, .cys_count determined from sequence outside
    # assumes order of pdb file
    my $self   = shift;
    my $mol_in = shift;
    my $name   = $mol_in->name;

    # strip hydrogens and water molecules
    my $mol =
      $mol_in->select_group(".not. Z 1")->select_group(".not. resname HOH");

    # all S atoms potential S-S bonds to cysteine, see 1v1q
    my $sg_group = $mol->select_group('symbol S');

    # altloc S makes this tricky
    my %SG_SEEN;

    unless ( $sg_group->count_atoms ) {
        warn "$name has no sulfurs\n";
        return;
    }

    my $bb = $mol->select_group("backbone");

    # for fast bond searching
    my @atoms = $mol->all_atoms;
    my $tree = Math::Vector::Real::kdTree->new( map { $_->xyz } @atoms );

    my @groups;
    foreach my $sg ( $sg_group->all_atoms ) {
        next unless ( $sg->resname eq 'CYS' and $sg->record_name eq "ATOM" );
        next
          if ( $SG_SEEN{ refaddr($sg) }++ )
          ;    # avoid overcount SG via altloc breakout below

        my $chain_id     = $sg->chain;
        my $auth_asym_id = $sg->auth_asym_id;
        my $entity_id    = $sg->entity_id;
        my $resid        = $sg->resid;
        my $serial       = $sg->serial;
        my $icode        = $sg->icode;
        my $altloc       = $sg->altloc;
        my $chain_cys    = {
            asym_id      => $chain_id,
            auth_asym_id => $auth_asym_id,
            entity_id    => $entity_id,
        };

        my $select = "resname CYS .and. resid $resid .and. chain $chain_id";
        $select .= " .and. .not. name OXT";  # ignore terminal oxygen, 1y2p.A.34
        $select .= " .and. icode  $icode" if $icode =~ /\S/;
        warn  "    icode check $name $chain_id $resid $icode\n"
          if ( $icode =~ /\S/ );

        my $cys    = $mol->select_group($select);
        my $cys_sc = $cys->select_group("name CB+SG");

        # this bb selection drops terminal extras...
        my $cys_bb       = $cys->select_group("backbone");
        my $cys_count    = $cys->count_atoms;
        my $cys_bb_count = $cys_bb->count_atoms;
        my $cys_sc_count = $cys_sc->count_atoms;

        if ( ( $cys_bb_count + $cys_sc_count ) != $cys_count ) {
            my $warn_msg = "    atom_count warning: $name $resid $serial:\n";
            $warn_msg .=   "        $cys_bb_count + $cys_sc_count = $cys_count?\n";
            die($warn_msg);
        }

        # Separate configurations using altloc, if needed:
        #    group atoms if they have same altloc or no altloc (altloc maps to alt_id in schema)
        #
        # avoid counting bonds within cys to avoid altloc conflicts
        my %THIS_SEEN = map { refaddr($_) => 1 } $cys->all_atoms;

        my @cys_splits;

        # assume no altloc defined if there are only 6 in the cysteine
        if ( $cys_bb_count == 4 and $cys_sc_count == 2 ) {
            push @cys_splits,
              {
                cys    => $cys,
                bb     => $cys_bb,
                sc     => $cys_sc,
                sg     => $sg,
                alt_id => undef,
              };
        }
        else {
            # accumulate configurations using altloc as described above
            my %alt_id;
            $alt_id{$_}++ foreach map { $_->altloc }
              grep { $_->altloc =~ /\S+/ } $cys->all_atoms;

          # create cysteines containing atoms with matching altloc or no altloc
            foreach my $alt_id ( sort keys %alt_id ) {
                my $lcys = HackaMol::AtomGroup->new(
                    atoms => [
                        grep { _select_atom_altloc( $_, $alt_id ) }
                          $cys->all_atoms
                    ]
                );

                my $lcys_bb = $lcys->select_group('backbone');
                my $lcys_sc = $lcys->select_group('name CB+SG');
                my ($lsg)   = $lcys->select_group('name SG')->all_atoms;
                $SG_SEEN{ refaddr($lsg) }++ if $lsg;

                if ( $lcys_bb->count_atoms == 4 and $lcys_sc->count_atoms == 2 )
                {
                    push @cys_splits,
                      {
                        cys    => $lcys,
                        bb     => $lcys_bb,
                        sc     => $lcys_sc,
                        sg     => $lsg,
                        alt_id => $alt_id
                      };
                }
                else {
                    # see 4urh for a particularly crazy case
                    my $warn_msg =
                      "Attempt to separate based on altloc failed:\n";
                    $warn_msg .=
                      "     bb.count : " . $lcys_bb->count_atoms . "\n";
                    $warn_msg .=
                      "     sc.count : " . $lcys_sc->count_atoms . "\n";
                    $warn_msg .= "     name     : " . $name . "\n";
                    $warn_msg .= "     chain_id : " . $chain_id . "\n";
                    $warn_msg .= "     sg_serial: " . $serial . "\n";
                    $warn_msg .= "     resid    : " . $resid . "\n";
                    $warn_msg .= "     alt_id   : " . $alt_id . "\n";

                    warn($warn_msg);
                }

            }
        }

        foreach my $cys_split (@cys_splits) {
            my $cys_bb = $cys_split->{bb};
            my $cys_sc = $cys_split->{sc};
            my $cys    = $cys_split->{cys};
            my $alt_id = $cys_split->{alt_id};
            my $sg     = $cys_split->{sg};

            # using the tree is a few orders of magnitude fasteri
            my @ix = $tree->find_in_ball( $sg->xyz, 3 );

            # logic in grep selects those with same altloc or no altloc
            my @cands =
              grep { _select_atom_altloc( $_, $alt_id ) }
              map { $atoms[$_] } @ix;

            # use THIS_SEEN to remove self comparisons, assumed to be 1 later
            my @bonds = HackaMol->new->find_bonds_brute(
                bond_atoms => [$sg],
                candidates => [ grep { !$THIS_SEEN{ refaddr($_) } } @cands ]
                ,    # 4urh bears witness to grep out self
                fudge => 0.25,    # 0.25 angstroms added
            );
            my $bond_count = scalar(@bonds);

            # assume the self term is one to avoid complications (4urh again);
            $bond_count++;

            my ( $cys_n, $cys_ca, $cys_c ) =
              map { $cys_bb->get_atoms($_) } ( 0, 1, 2 );

            my %bb_angle_hash = ();

            my ( $omega_at, $phi_at, $psi_at );
            my $n_cov = $cys_n->covalent_radius;
            my $c_cov = $cys_c->covalent_radius;

            my $chain = $bb->select_group("chain $chain_id");

            my $psi_g = $chain->select_group("name N");

            # look for psi atom using distances.  meta data is not reliable
            # if there are insertion codes
            ($psi_at) =
              grep { $cys_c->distance($_) <= $c_cov + $n_cov + 0.25 }
              $psi_g->all_atoms;

            my $phi_g = $chain->select_group("name C");

            # look for phi atom using distances.  meta data is not reliable
            # if there are insertion codes
            ($phi_at) =
              grep { $cys_n->distance($_) <= $c_cov + $n_cov + 0.25 }
              $phi_g->all_atoms;

            if ($phi_at) {

                my $omega_g = $chain->select_group("name CA");

                # look for phi atom using distances.  meta data is not reliable
                # if there are insertion codes
                ($omega_at) =
                  grep { $phi_at->distance($_) <= $c_cov + $c_cov + 0.25 }
                  $omega_g->all_atoms;

            }
            %bb_angle_hash = (
                omega => $omega_at ? HackaMol::Dihedral->new(
                    atoms => [ $omega_at, $phi_at, $cys_n, $cys_ca ]
                  ) : undef,
                phi => $phi_at ? HackaMol::Dihedral->new(
                    atoms => [ $phi_at, $cys_n, $cys_ca, $cys_c ]
                  ) : undef,
                psi => $psi_at ? HackaMol::Dihedral->new(
                    atoms => [ $cys_n, $cys_ca, $cys_c, $psi_at ]
                ) : undef,
            );

    # allow bb angles to pass through only if they contain atoms of all the same
    # altloc (may be undef)
            foreach my $ang_name ( keys %bb_angle_hash ) {
                if ( $bb_angle_hash{$ang_name} ) {

                    # all atoms must be of single altloc '' type
                    my %alt_seen;
                    $alt_seen{$_}++ foreach map {
                        my $alt = $_->altloc;
                        defined($alt) ? $alt : 'NULL'
                    } $bb_angle_hash{$ang_name}->all_atoms;

                    $bb_angle_hash{$ang_name} = undef
                      unless scalar( keys %alt_seen ) == 1;
                }
            }

            my $big_group = HackaMol::AtomGroup->new(
                atoms => [
                    grep { $_ } ( $omega_at, $phi_at ), $cys_bb->all_atoms,
                    $cys_sc->all_atoms, grep { $_ } ($psi_at),
                ]
            );

            push @groups,
              {
                SG_occ        => sprintf( "%.2f", $sg->occ ),
                alt_id        => $alt_id,
                SG_bond_count => $bond_count,
                chain_cys     => $chain_cys,
                cys_mol       => $big_group,
                bb            => $cys_bb,
                sc            => $cys_sc,
                %bb_angle_hash,
              };

        }

    }
    return @groups;
}

sub _select_atom_altloc {

    # ->altloc default is currently ' ' in hackamol (0.050)
    #        written against possibility of becoming . as in mmCIF or undef
    #
    # return true if atom->altloc matches alt_id
    # a match is true if:
    #          atom->altloc eq alt_id
    #          (atom->altloc|alt_id) !~ /\S+/  or either is undef
    my ( $atom, $alt_id ) = @_;

    my $bool = 1;
    if ( $alt_id && $alt_id =~ /\S+/ ) {
        my $altloc = $atom->altloc;
        if ( $altloc && $altloc =~ /\S+/ ) {
            $bool = $altloc eq $alt_id;
        }
    }
    return $bool;
}

sub build_cys {
    my $self     = shift;
    my $cys_conf = shift;    

    #my $resid     = $cys_conf->cys_id;
    my $resid     = $cys_conf->cys->auth_seq_id || " ";
    my $icode     = $cys_conf->cys->insert_code || " ";
    my $sg_serial = $cys_conf->SG_serial;
    my $sg_occ    = $cys_conf->SG_occ;
    my $ca_bfact  = $cys_conf->CA_bfact;
    my $chain_id  = $cys_conf->chain_id;
    my $model_num = $cys_conf->model_num;
    my $alt_id    = $cys_conf->alt_id ;

    my $serial = $sg_serial - 5;    # n serial
    my @atoms  = map {
        my %alt = $alt_id ? (altloc => $alt_id): ();
        HackaMol::Atom->new(
            record_name => 'ATOM',
            name        => $_,
            resid       => $resid,
            serial      => $serial++,
            symbol      => substr( $_, 0, 1 ),
            occ         => $sg_occ, # lump all into having same occ
            bfact       => 0,
            resname     => 'CYS',
            chain       => $chain_id,
            model_num   => $model_num,
            %alt, # we lump all atoms into altloc even though this may not be true in the actual cif
          )
    } qw(N CA C O CB SG);

    $atoms[1]->bfact($ca_bfact);

    my $xyzs = $self->cys_conf_mvrs($cys_conf);
    foreach my $i ( 0 .. $#atoms ) {
            $atoms[$i]->push_coords( $xyzs->[$i] );
    }

    my $mol = HackaMol::Molecule->new(
        name  => $cys_conf->id,
        atoms => \@atoms,
    );

    return $mol;

}

sub build_cyd {

    # expects in the order given in ext_cys
    my $self     = shift;
    my $cysi     = shift;
    my $cysj     = shift;
    my $mol_code = shift;                       # if $mol_code == 0
    my $mol      = HackaMol::Molecule->new();

    my @at_i = $cysi->all_atoms;
    my @at_j = $cysj->all_atoms;
    $mol->push_atoms( @at_i[ 0 .. 5 ] );
    $mol->push_atoms( $at_i[6] ) unless ( $mol_code == 0 );
    $mol->push_atoms( @at_i[ 7 .. 11 ] );
    $mol->push_atoms( $at_i[12] ) unless ( $mol_code == 0 );
    $mol->push_atoms( @at_j[ 0 .. 6 ] );
    if ( $mol_code == 0 ) {

        #keep the best HN
        my $c = $cysi->get_atoms(2);
        my ($h) =
          sort { $c->distance($b) <=> $c->distance($a) } @at_j[ 7, 8 ];
        $mol->push_atoms($h);
    }
    else {
        $mol->push_atoms( @at_j[ 7, 8 ] );
    }
    $mol->push_atoms( @at_j[ 9 .. 12 ] );
    return $mol;
}

=head2 extend_cys

    add hydrogens and hydroxide to PDB cys for gas-phase molecule 

    note: this depends on order of atoms being that from a PDB, N_CA_C_O_CB_S 

    arguments: cys (HackaMol::Molecule), reduce_flag (0,1)  add H to SG if reduced

    returns extended molecule, in this order:
    O .. 5 : N_CA_C_O_CB_S  as in the orginal pdb
    
    6.  OB
    7.  HN1 
    8.  HN2
    9.  HCA
    10. HCB1 
    11. HCB2 
    12. HOB     
    13. HSG   # will not be built if reduced flag not true

=cut

sub extend_cys {
    my $self        = shift;
    my $cys         = shift;
    my $reduce_flag = shift;

    my @atoms  = $cys->all_atoms;
    my $chain  = $atoms[0]->chain;
    my $serial = $atoms[-1]->serial;
    my $resid  = $atoms[-1]->resid;

    # first extend metadata
    my @cys_ext = (
        @atoms,
        HackaMol::Atom->new( Z => 8, name => 'OB',   serial => ++$serial ),
        HackaMol::Atom->new( Z => 1, name => 'HN1',  serial => ++$serial ),
        HackaMol::Atom->new( Z => 1, name => 'HN2',  serial => ++$serial ),
        HackaMol::Atom->new( Z => 1, name => 'HCA',  serial => ++$serial ),
        HackaMol::Atom->new( Z => 1, name => 'HCB1', serial => ++$serial ),
        HackaMol::Atom->new( Z => 1, name => 'HCB2', serial => ++$serial ),
        HackaMol::Atom->new( Z => 1, name => 'HOB',  serial => ++$serial ),
    );

    # push on hsg if reduced
    if ($reduce_flag) {
        push @cys_ext,
          HackaMol::Atom->new( Z => 1, name => 'HSG', serial => ++$serial );
    }

    # fix up some common metadata
    foreach my $atom (@cys_ext) {
        $atom->resname('CYS');
        $atom->record_name('ATOM');
        $atom->resid($resid);
        $atom->chain($chain);
    }

    #now push coordinates on to the atoms
    foreach my $t ( 0 .. $cys->tmax ) {
        $cys->gt($t);

        # OB
        $cys_ext[6]->push_coords(
            $bldr->extend_abc(
                ( map { $_->xyz } @atoms[ 3, 1, 2 ] ),
                1.36, 119.5, 180
            ),
        );

        # HN1
        $cys_ext[7]->push_coords(
            $bldr->extend_abc(
                ( map { $_->xyz } @atoms[ 2, 1, 0 ] ),
                1.0, 123.9300, 180
            ),
        );

        # HN2
        $cys_ext[8]->push_coords(
            $bldr->extend_abc(
                ( map { $_->xyz } @atoms[ 2, 1, 0 ] ),
                1.0, 123.9300, 0
            ),
        );

        # HCA
        $cys_ext[9]->push_coords(
            $bldr->extend_abc(
                ( map { $_->xyz } @atoms[ 0, 2, 1 ] ), 1.0,
                107.7100, -116.3400
            ),
        );

        # HCB1
        $cys_ext[10]->push_coords(
            $bldr->extend_abc(
                ( map { $_->xyz } @atoms[ 5, 1, 4 ] ), 1.0,
                107.2400, 119.9100
            ),
        );

        # HCB2
        $cys_ext[11]->push_coords(
            $bldr->extend_abc(
                ( map { $_->xyz } @atoms[ 5, 1, 4 ] ), 1.0,
                107.2400, -125.3200
            ),
        );

        # HOB
        $cys_ext[12]->push_coords(
            $bldr->extend_abc(
                ( map { $_->xyz } @cys_ext[ 3, 2, 6 ] ),
                1.0, 109.5, 0
            ),
        );

        # HOB
        if ($reduce_flag) {
            $cys_ext[13]->push_coords(
                $bldr->extend_abc(
                    ( map { $_->xyz } @cys_ext[ 1, 4, 5 ] ), 1.33,
                    92.0, 180
                ),
            );
        }

    }

    return HackaMol::Molecule->new( atoms => \@cys_ext );

}

sub cys_conf_mvrs {

    # retun list of xyzs from a conformation,
    # N,CA,C,O,CB,SG
    my $self = shift;
    my $conf = shift;
    my @xyzs;

    # backbone
    foreach my $bb (qw(N CA C O)) {
        my $gx = "$bb\_x";
        my $gy = "$bb\_y";
        my $gz = "$bb\_z";
        push @xyzs, V( $conf->$gx, $conf->$gy, $conf->$gz );
    }

    #sidechain CB and SG
    my $cb = $bldr->extend_abc( @xyzs[ 3, 2, 1 ],
        $conf->CA_CB, $conf->C_CA_CB, $conf->O_C_CA_CB );

    # tidy up the sig figs for consistent future calculations
    push @xyzs, V( map { sprintf( "%.3f", $_ ) } @{$cb} );
    my $sg = $bldr->extend_abc( @xyzs[ 0, 1, 4 ],
        $conf->CB_SG, $conf->CA_CB_SG, $conf->N_CA_CB_SG );
    push @xyzs, V( map { sprintf( "%.3f", $_ ) } @{$sg} );
    return \@xyzs;

}

no Moose::Role;
1;
