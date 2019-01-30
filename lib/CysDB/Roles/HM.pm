package CysDB::Roles::HM;

# ABSTRACT: pull out Cysteine disulfide info from pdb
use Moose::Role;
use Math::Trig;
use HackaMol;

with 'CysDB::Roles::HMCys';

my %ss_class = (
    "00000" => "-LHSpiral",
    "01100" => "-RHHook",
    "00110" => "-RHHook",
    "10000" => "+/-LHSpiral",
    "00001" => "+/-LHSpiral",
    "00010" => "-LHHook",
    "01000" => "-LHHook",
    "11100" => "-/+RHHook",
    "00111" => "-/+RHHook",
    "00100" => "-RHStaple",
    "11110" => "+/-RHSpiral",
    "01111" => "+/-RHSpiral",
    "01110" => "-RHSpiral",
    "11000" => "-/+LHHook",
    "00011" => "-/+LHHook",
    "10010" => "+/-LHHook",
    "01001" => "+/-LHHook",
    "11111" => "+RHSpiral",
    "10110" => "+/-RHHook",
    "01101" => "+/-RHHook",
    "11010" => "+/-LHStaple",
    "01011" => "+/-LHStaple",
    "01010" => "-LHStaple",
    "10011" => "+LHHook",
    "11001" => "+LHHook",
    "10001" => "+LHSpiral",
    "10100" => "+/-RHStaple",
    "00101" => "+/-RHStaple",
    "11101" => "+RHHook",
    "10111" => "+RHHook",
    "10101" => "+RHStaple",
    "11011" => "+LHStaple",
);

sub cys_tables {
    my $self      = shift;
    my $cys_group = shift;

        my $pdb_id    = $cys_group->{pdb_id};
        my $entity_id = $cys_group->{entity_id};
        my $sg_bond_count = $cys_group->{SG_bond_count};

        my $cys_mol   = $cys_group->{cys_mol};
        my $sc        = $cys_group->{sc};
        my $bb        = $cys_group->{bb};
        my $omega     = $cys_group->{omega};
        my $phi       = $cys_group->{phi};
        my $psi       = $cys_group->{psi};

        # O-C-CA-CB  C-CA-CB  CA-CB
        # N-CA-CB-SG CA-CB-SG CB-SG
        my $n  = $bb->get_atoms(0);
        my $ca = $bb->get_atoms(1);
        my $c  = $bb->get_atoms(2);
        my $o  = $bb->get_atoms(3);
        my $cb = $sc->get_atoms(0);
        my $sg = $sc->get_atoms(1);
        my $o_c_ca_cb =
          HackaMol::Dihedral->new( atoms => [ $o, $c, $ca, $cb ] );
        my $c_ca_cb = HackaMol::Angle->new( atoms => [ $c, $ca, $cb ] );
        my $ca_cb = HackaMol::Bond->new( atoms => [ $ca, $cb ] );
        my $n_ca_cb_sg =
          HackaMol::Dihedral->new( atoms => [ $n, $ca, $cb, $sg ] );
        my $ca_cb_sg = HackaMol::Angle->new( atoms => [ $ca, $cb, $sg ] );
        my $cb_sg = HackaMol::Bond->new( atoms => [ $cb, $sg ] );

        my $cys_table = {
            pdb_id      => $cys_group->{pdb_id},
            entity_id   => $cys_group->{entity_id},
            chain_id    => $cys_group->{chain_id},
            seq_id      => $sg->resid,
            auth_seq_id => $sg->auth_seq_id,
            insert_code => $sg->icode =~ /\S/ ? $sg->icode : undef,
        };

        my $cys_conf   = {
            pdb_id      => $cys_group->{pdb_id},
            entity_id   => $cys_group->{entity_id},
            chain_id    => $cys_group->{chain_id},
            CA_bfact    => sprintf("%.2f",$ca->bfact),
            model_num   => $sg->model_num,
            alt_id      => $cys_group->{alt_id},
            omega => $omega ? sprintf( "%.3f", $omega->dihe_deg ) : undef,
            phi => $phi ? sprintf( "%.3f", $phi->dihe_deg ) : undef,
            psi => $psi ? sprintf( "%.3f", $psi->dihe_deg ) : undef,
            SG_serial   => $sg->serial,
            SG_occ      => $cys_group->{SG_occ},
            SG_bond_count  => $cys_group->{SG_bond_count},
            "O_C_CA_CB"    => sprintf( "%.3f", $o_c_ca_cb->dihe_deg ),
            "C_CA_CB"      => sprintf( "%.3f", $c_ca_cb->ang_deg ),
            "CA_CB"        => sprintf( "%.3f", $ca_cb->bond_length ),
            "N_CA_CB_SG"   => sprintf( "%.3f", $n_ca_cb_sg->dihe_deg ),
            "CA_CB_SG"     => sprintf( "%.3f", $ca_cb_sg->ang_deg ),
            "CB_SG"        => sprintf( "%.3f", $cb_sg->bond_length ),
            };

            ( $cys_conf->{N_x}, $cys_conf->{N_y}, $cys_conf->{N_z} ) =
              map { sprintf( "%.3f", $_ ) } @{ $n->xyz };
            ( $cys_conf->{CA_x}, $cys_conf->{CA_y}, $cys_conf->{CA_z} ) =
              map { sprintf( "%.3f", $_ ) } @{ $ca->xyz };
            ( $cys_conf->{C_x}, $cys_conf->{C_y}, $cys_conf->{C_z} ) =
              map { sprintf( "%.3f", $_ ) } @{ $c->xyz };
            ( $cys_conf->{O_x}, $cys_conf->{O_y}, $cys_conf->{O_z} ) =
              map { sprintf( "%.3f", $_ ) } @{ $o->xyz };
    return ($cys_table,$cys_conf);
}

sub cys_cys_table {
    my $self = shift;
    my %args = @_;

    my $cys_i = $args{cys_i};
    my $cys_j = $args{cys_j};
    die "two cysteines required with no hydrogen"
      unless ( $cys_i->total_mass == $cys_j->total_mass
        and $cys_i->bin_atoms_name eq "SONC3" );

    my $pdb_id = uc( $args{pdb_id} );
    my $cys_conf_idi = $args{cys_conf_idi};
    my $cys_conf_idj = $args{cys_conf_idj};
    my $entity_idi = $args{entity_idi};
    my $entity_idj = $args{entity_idj};
    my $chain_idi = $args{chain_idi};
    my $chain_idj = $args{chain_idj};
    my $alt_id_sum = $args{alt_id_sum};
    my $alt_occ_flag = $args{alt_occ_flag};



    my ( $n_i, $ca_i, $c_i, $cb_i, $sg_i ) = map { $cys_i->get_atoms($_) } 0,
      1, 2, 4, 5;
    my ( $n_j, $ca_j, $c_j, $cb_j, $sg_j ) = map { $cys_j->get_atoms($_) } 0,
      1, 2, 4, 5;


    my $ss   = sprintf( "%.3f", $sg_i->distance($sg_j) );  
    my $caca = sprintf( "%.3f", $ca_i->distance($ca_j) );

    my $cbss = sprintf( "%.3f",
        HackaMol::Angle->new( atoms => [ $cb_i, $sg_i, $sg_j ] )->ang_deg );
    my $sscb = sprintf( "%.3f",
        HackaMol::Angle->new( atoms => [ $sg_i, $sg_j, $cb_j ] )->ang_deg );
    my $ncacbs = sprintf( "%.3f",
        HackaMol::Dihedral->new( atoms => [ $n_i, $ca_i, $cb_i, $sg_i ] )
          ->dihe_deg );
    my $cacbss = sprintf( "%.3f",
        HackaMol::Dihedral->new( atoms => [ $ca_i, $cb_i, $sg_i, $sg_j ] )
          ->dihe_deg );
    my $sscbca = sprintf( "%.3f",
        HackaMol::Dihedral->new( atoms => [ $sg_i, $sg_j, $cb_j, $ca_j ] )
          ->dihe_deg );
    my $cbsscb = sprintf( "%.3f",
        HackaMol::Dihedral->new( atoms => [ $cb_i, $sg_i, $sg_j, $cb_j ] )
          ->dihe_deg );
    my $scbcan = sprintf( "%.3f",
        HackaMol::Dihedral->new( atoms => [ $n_j, $ca_j, $cb_j, $sg_j ] )
          ->dihe_deg );

    my $dse =
      #1.4 * ( 1 + cos( 3 * deg2rad($ncacbs) ) ) +  # 2.0 in katz, kossiakof 1986
      #1.4 * ( 1 + cos( 3 * deg2rad($scbcan) ) ) +  # 2.0 in katz, 1.4 in AMBER
      2.0 * ( 1 + cos( 3 * deg2rad($ncacbs) ) ) +  # 2.0 in katz, kossiakof 1986
      2.0 * ( 1 + cos( 3 * deg2rad($scbcan) ) ) +  # 2.0 in katz
      1.0 * ( 1 + cos( 3 * deg2rad($cacbss) ) ) +
      1.0 * ( 1 + cos( 3 * deg2rad($sscbca) ) ) +
      3.5 * ( 1 + cos( 2 * deg2rad($cbsscb) ) ) +
      0.6 * ( 1 + cos( 3 * deg2rad($cbsscb) ) );

    my $mol_code = 1;
    $mol_code = 2 if ( $sg_i->chain ne $sg_j->chain );
    $mol_code = 0
      if ( $n_j->distance($c_i) < 1.71 or $n_i->distance($c_j) < 1.71 ); # n->cov + c->cov + 0.25

    my $class_key = join '',
      map { $_ < 0 ? 0 : 1 } ( $ncacbs, $cacbss, $cbsscb, $sscbca, $scbcan );
    my $class = $ss_class{$class_key};

    my %cys_cys_table;
    $cys_cys_table{pdb_id}          = uc($pdb_id);
    $cys_cys_table{entity_idi}      = $entity_idi;
    $cys_cys_table{entity_idj}      = $entity_idj;
    $cys_cys_table{chain_idi}       = $chain_idi;
    $cys_cys_table{chain_idj}       = $chain_idj;
    $cys_cys_table{cys_conf_idi}    = $cys_conf_idi;
    $cys_cys_table{cys_conf_idj}    = $cys_conf_idj;
    $cys_cys_table{alt_id_sum}      = $alt_id_sum;
    $cys_cys_table{alt_occ_flag}    = $alt_occ_flag;
    $cys_cys_table{SGi_SGj}         = $ss;
    $cys_cys_table{CAi_CAj}         = $caca;
    $cys_cys_table{CBi_SGi_SGj}     = $cbss;
    $cys_cys_table{SGi_SGj_CBj}     = $sscb;
    $cys_cys_table{CAi_CBi_SGi_SGj} = $cacbss;
    $cys_cys_table{CBi_SGi_SGj_CBj} = $cbsscb;
    $cys_cys_table{SGi_SGj_CBj_CAj} = $sscbca;
    $cys_cys_table{dse}             = sprintf( "%.1f", 4.184 * $dse );
    $cys_cys_table{mol_code}        = $mol_code;
    $cys_cys_table{class}           = $class;

    return \%cys_cys_table;

}

sub _trim {
    my $str = shift;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

no Moose::Role;
1;
