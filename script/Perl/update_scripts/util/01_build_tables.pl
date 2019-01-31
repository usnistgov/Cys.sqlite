#!/usr/bin/env perl
#
use Modern::Perl;
use Path::Tiny;
use lib 'lib';
use CysDB;
use HackaMol;
use JSON::PP;
use POSIX qw(strftime);
use Scalar::Util qw(refaddr);
use Try::Tiny;
use Data::Dumper;

my $fjson = shift; # || die "need to pass in json file with list of pdbids";
my $pdbids = JSON::PP->new->decode( path($fjson)->slurp );

# if you would like to load all cifs in local storage. set fjson = 0 and comment out $pdbids = JSON::PP  ...

my $CysDB = CysDB->new;

#unlink 'cys.sqlite';
my $schema = CysDB::Schema->connect('dbi:SQLite:cys.sqlite');
$schema->deploy unless -e 'cys.sqlite';

my $bldr = HackaMol->new();

my @processed;

my @pdbids = $fjson ? map {$bldr->pdbid_local_path($_)} @$pdbids : sort $bldr->local_cifs();

my $entity_rs = $schema->resultset('EntityCys');
my $pdb_rs    = $schema->resultset('PDB');
my $chain_rs  = $schema->resultset('ChainCys');
my $cys_rs    = $schema->resultset('Cys');
my $conf_rs   = $schema->resultset('CysConf');

#flush it
$| = 1;

# some inital tests
my $regex = join "|", qw/
4urh
2a31
3ago
6ayn
6az1
2bax
2bch
1dx5
2fcw
1flr
1y2p
1v1q
1gvk
1h0g
2h5d
1hje
/;

#@pdbids = grep { m/$regex/i } @pdbids;

foreach my $cif_file ( @pdbids) {

    try {
        $schema->txn_do(
            sub {

                my $pdbid = $cif_file->basename(qr/.cif/);

                # skip if done already
                if ( $schema->resultset('PDB')->find( { id => uc($pdbid) } ) ) {
                    my $date = strftime '%Y-%m-%d_%H:%M.%S', localtime();
                    say "$date: skipping $pdbid, found in cys.sqlite";
                }
                else {
                    my $date = strftime '%Y-%m-%d_%H:%M.%S', localtime();
                    say "$date: loading $cif_file";

                    my $cif_file = $bldr->pdbid_local_path($pdbid);
                    my ( $info, $mols ) = $bldr->read_file_cif_parts($cif_file);

                    # Populate PDB table; 
                    #   update .cys_count .res_count .chain_count after entity and chain load
                    my $pdb_col_data = {};
                    $pdb_col_data->{id}         = uc($pdbid);
                    $pdb_col_data->{exp_method} = $info->{exp_method}
                      || die "no exp_method";
                    $pdb_col_data->{resolution} = $info->{resolution};
                    $pdb_col_data->{keywords}   = $info->{keywords};
                    die "no keywords"
                      unless ( $pdb_col_data->{keywords}
                        && $pdb_col_data->{keywords} =~ /\S+/ );
                    $pdb_col_data->{deposition_date} = $info->{deposition_date}
                      || die "no deposition date";
                    $pdb_col_data->{last_revision_date} =
                      $info->{last_revision_date}
                      || die "no revision date";
                    $pdb_col_data->{cys_count}   = 0;
                    $pdb_col_data->{chain_count} = 0;
                    $pdb_col_data->{res_count}   = 0;
                    $pdb_col_data->{status} = 'CURRENT';
                    my $pdb_entry = $pdb_rs->create($pdb_col_data);
                    my $pdb_id_fk = $pdb_entry->id;

                    # Populate EntityCys table:
                    #   we first parse the coordinates to cull the sequences to those related 
                    #   to the cysteine information. i.e. throw away DNA sequences (also have C!)
                    my %entity_all = %{ $info->{entity} };
                    my %entity_cys;
                    my %chain_cys;

                    # PDB columns to be updated below
                    my $cys_total   = 0;
                    my $res_total   = 0;
                    my $chain_total = 0;

                    my %GROUPS;
                    foreach my $mol (@$mols) {
                        $mol->name( $pdbid . "." . $mol->name );
                        my @cys_groups = $CysDB->cys_groups($mol);
                        $GROUPS{ refaddr($mol) } = \@cys_groups;

                        #bond_count for sg determined using 0.25 fudge
                        foreach my $cys_group (@cys_groups) {
                            my $lchain_cys = $cys_group->{chain_cys};
                            my $entity_id  = $lchain_cys->{entity_id};
                            die "no known entity"
                              unless exists( $entity_all{$entity_id} );
                            $lchain_cys->{pdbx_entity_id} = $entity_id;

                            # collect relevant entities
                            $entity_cys{$entity_id} = $entity_all{$entity_id};

                            # collect unique CysChain hashes to populate entries
                            if ( exists( $chain_cys{$entity_id} ) ) {
                                my ($seen) =
                                  grep {
                                    $lchain_cys->{asym_id} eq $_->{asym_id}
                                  } @{ $chain_cys{$entity_id} };
                                if ($seen) {

          # throw away the copies, this allows us to attach entity_id, etc below
                                    $cys_group->{chain_cys} = $seen;
                                }
                                else {
                                    push @{ $chain_cys{$entity_id} },
                                      $lchain_cys
                                      unless $seen;
                                }
                            }
                            else {
                                $chain_cys{$entity_id} = [$lchain_cys];
                            }

                        }
                    }

                    foreach
                      my $entity_id ( sort { $a <=> $b } keys %entity_cys )
                    {
                        my $seq =
                          $entity_cys{$entity_id}
                          {'_entity_poly.pdbx_seq_one_letter_code_can'}
                          || die 'undefined sequence';
                        my $res_count = length($seq);
                        my $cys_count = () = $seq =~ /c/ig;

                        my $entity_entry = $entity_rs->find_or_create(
                            {
                                sequence  => $seq,
                                cys_count => $cys_count,
                                res_count => $res_count,
                            }
                        );
                        my $entity_id_fk = $entity_entry->id;

                        foreach my $chain_cys ( @{ $chain_cys{$entity_id} } ) {
                            $cys_total += $cys_count;
                            $res_total += $res_count;
                            $chain_total++;
                            my $id = $chain_rs->get_column('id')->max + 1;
                            $chain_cys->{id}        = $id;
                            $chain_cys->{entity_id} = $entity_id_fk;
                            $chain_cys->{pdb_id}    = $pdb_id_fk;
                            $chain_rs->create($chain_cys);
                        }
                    }

                    # update PDB based on info collected above
                    $pdb_entry->update(
                        {
                            cys_count   => $cys_total,
                            res_count   => $res_total,
                            chain_count => $chain_total,
                        }
                    );

                    # load Cys and Cys_conf
                    foreach my $mol (@$mols) {
                        my $cys_groups = $GROUPS{ refaddr($mol) };
                        foreach my $cys_group (@$cys_groups) {
                            $cys_group->{pdb_id} = $pdb_id_fk;
                            $cys_group->{entity_id} =
                              $cys_group->{chain_cys}{entity_id};
                            $cys_group->{chain_id} =
                              $cys_group->{chain_cys}{id};
                            my ( $cys_table, $cys_conf ) =
                              $CysDB->cys_tables($cys_group);
                            my $cys_entry = $cys_rs->find_or_create($cys_table);
                            eval {
                                $cys_entry->create_related( 'cys_conf',
                                    $cys_conf );
                                1;
                            } or do {
                                print Dumper $cys_rs->find($cys_table)
                                  ->get_columns;

                                # print Dumper $cys_conf_rs->find( {
                                #
                                #    } );
                                print Dumper $cys_table, $cys_conf;
                                die "deadmeat: $@\n";
                              }
                        }
                    }
                    my $cys_count =
                      $cys_rs->search( { pdb_id => $pdb_id_fk } )->count;
                    my $chain_count =
                      $chain_rs->search( { pdb_id => $pdb_id_fk } )->count;
                    my $conf_count =
                      $conf_rs->search( { pdb_id => $pdb_id_fk } )->count;
                    $date = strftime '%Y-%m-%d_%H:%M.%S', localtime();
                    print "$date: $pdb_id_fk loaded: "; 
                    print " $chain_count chains, $cys_count/$cys_total CYS/cys_seq, $conf_count configs\n";
                }
            }
          )
    }
    catch {
        my $date = strftime '%Y-%m-%d_%H:%M.%S', localtime();
        print "$date: $cif_file failed!\n$_\n";
    }
}

