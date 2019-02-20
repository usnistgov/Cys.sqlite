use Modern::Perl;
use Path::Tiny;
use JSON::PP;
use lib 'lib';
use CysDB;
use HackaMol;
use POSIX qw(strftime);
use Data::Dumper;

my $json_file_override = shift;

my $CysDB = CysDB->new();
my ( $json_file, $pdbids, $all_pdbids ) = SYNC_cifs($json_file_override);

#update those that are now obsolete
my @obsolete = $CysDB->update_obsolete();
say "Cys.sqlite obsolete entries: @obsolete";

my $log_file = "build_cys-sqlite.log";

#load everything but the Cys Cys table entries
load_cifs( $json_file, $log_file );

#pdbids_load_cys_cys($CysDB,['1Y20'],$log_file); # simple test

pdbids_load_cys_cys( $CysDB, $pdbids, $log_file );

exit;

sub load_cifs {
    my $json_file = shift;
    my $log_file  = shift;
    say
"running the load script/Perl/update_scripts/util/01_build_tables.pl on $json_file. appending to build_cys-sqlite.log";
    system("perl script/Perl/update_scripts/util/01_build_tables.pl $json_file >> $log_file");
}

sub SYNC_cifs {

#die "run this as much as you want! but it will take a long time to sync an empty dir";
    my $json_file_override = shift;
    my $CysDB              = CysDB->new();

    my $bldr_json = JSON::PP->new();

    my @pdbids;
    if ($json_file_override) {
        say "fetching pdbids from $json_file_override";
        $pdbids = $bldr_json->decode( path($json_file_override)->slurp );
        @pdbids = $CysDB->check_pdbids($pdbids);
        say "@{[scalar(@pdbids)]} outstainding pdbids retrieved from json file";
    }
    else {
        say "fetching all pdbids with 1 or more disulfide bonds from RCSB";
        @pdbids = $CysDB->check_pdbids([$CysDB->fetch_rcsb_pdbids()]);
        say "@{[scalar(@pdbids)]} outstanding pdbids were retrieved from the RCSB";
    }

    die "nothing to be synced" unless @pdbids;

    my $bldr      = HackaMol->new();

    my ( $synced_pdbids, $missed_pdbids ) = ( [], [] );

    say "syncing missing protein databank files to @{[ $bldr->local_cif_path ]}";
    ( $synced_pdbids, $missed_pdbids ) = $bldr->rcsb_sync_local( 'cif', @pdbids );

    if ( scalar(@$missed_pdbids) ) {
        warn "MISSED PDBIDS!\n";
        warn "   $_" foreach @$missed_pdbids;
        die "please check methods or report issue";
    }

    if ( scalar(@$synced_pdbids) != scalar(@pdbids) ) {
        warn "@{[scalar(@$synced_pdbids)]} files synced;  @{[scalar(@pdbids)]} pdbids to be loaded";
    }

    my $date = strftime '%Y-%m-%d', localtime();

    my $db_loads_path = path("db_loads");
    $db_loads_path->mkpath unless $db_loads_path->exists;

    #add incrementing postfix on date in filename if exists
    my $i = 0;
    while ( $db_loads_path->children(qr/$date\w+_$i\.json/) ) {
        $i++;
    }

    my $sync_path = $db_loads_path->child("${date}_loadlist_$i.json");
    $sync_path->spew(
        JSON::PP->new()->pretty->canonical->encode(\@pdbids) );

    say "stored synced pdbids in @{[$sync_path->stringify]}";
    return ( $sync_path->stringify, \@pdbids );
}

sub pdbids_load_cys_cys {
    my $CysDB    = shift;
    my $pdbids   = shift;
    my $log_file = shift;

    my $fh = path($log_file)->filehandle( { locked => 1 }, ">>" );

    my $ss_cutoff =
      2.31;    # 2*covalent radius + 0.25 angstrom (fudge used in bond search)
    my $schema = $CysDB->schema;
    my $PDB_rs = $schema->resultset('PDB')
      ->search( {}, { prefetch => { 'cys_conf' => 'cys' } } );
    my $cys_cys_rs = $schema->resultset('CysCys');

    foreach my $pdb_id (@$pdbids) {
        my $pdb = $PDB_rs->find( uc($pdb_id) );

        my $date = strftime '%Y-%m-%d_%H:%M.%S', localtime();
        print $fh "$date $pdb_id: loading cys_cys\n";

        my @cys_confs = $pdb->cys_conf;

        # build list of potential cys
        my %cys;
        foreach my $cys_conf (@cys_confs) {
            next
              unless $cys_conf->SG_bond_count ==
              2; # potential bug if 0.25 \AA\ fudge is changed in the HMCys role

            my $cys =
              $CysDB->build_cys($cys_conf);    #cys_conf->id stored in cys->name
             # all cys with same id and model_num get pushed together, separated by model_num
            push @{ $cys{ $cys_conf->cys_id }{ $cys_conf->model_num }{meta} },
              {
                cys_conf_id => $cys_conf->id,
                entity_id   => $cys_conf->entity_id,
                chain_id    => $cys_conf->chain_id,
              };
            push @{ $cys{ $cys_conf->cys_id }{ $cys_conf->model_num }{cys} },
              $cys;
        }

# each cys_id corresponds to 1 or more cys geometries (different models, different alt_id)
        my @cys_ids = sort { $a <=> $b } keys %cys;

        my $ss_count      = 0;
        my $ss_in_storage = 0;

        # loop over the first cys
        foreach my $i ( 0 .. $#cys_ids ) {

            my $key_i        = $cys_ids[$i];
            my $cys_models_i = $cys{$key_i};

            # loop over the model_num, this is THE model_num for both
            foreach my $model_num ( sort { $a <=> $b } keys %{$cys_models_i} ) {

                my $cys_is  = $cys_models_i->{$model_num}{cys};
                my $meta_is = $cys_models_i->{$model_num}{meta};

                # loop over the second cys
                foreach my $j ( $i + 1 .. $#cys_ids ) {
                    my $key_j   = $cys_ids[$j];
                    my $cys_js  = $cys{$key_j}{$model_num}{cys};
                    my $meta_js = $cys{$key_j}{$model_num}{meta};

         # the alt_id loop
         #   alt_id is the only way $cys_i or $cys_j to have more than one entry
                    foreach my $ii ( 0 .. $#{$cys_is} ) {

                        my $cys_i  = $cys_is->[$ii];
                        my $meta_i = $meta_is->[$ii];

                        my $sg_i     = $cys_i->get_atoms(5);
                        my $alt_id_i = $sg_i->altloc;
                        my $occ_i    = $sg_i->occ;

                        foreach my $jj ( 0 .. $#{$cys_js} ) {
                            my $cys_j  = $cys_js->[$jj];
                            my $meta_j = $meta_js->[$jj];

                            my $sg_j     = $cys_j->get_atoms(5);
                            my $alt_id_j = $sg_j->altloc;
                            my $occ_j    = $sg_j->occ;

                            my $alt_id_sum = 0;
                            $alt_id_sum++
                              if $alt_id_i
                              && length($alt_id_i)
                              && $alt_id_i =~ /\S+/;
                            $alt_id_sum++
                              if $alt_id_j
                              && length($alt_id_j)
                              && $alt_id_j =~ /\S+/;

                            next
                              if ( $alt_id_sum == 2 && $alt_id_i ne $alt_id_j );

                            my $alt_occ_flag = undef;
                            $alt_occ_flag = 'Y' if $alt_id_sum > 0;
                            $alt_occ_flag = 'Y' if $occ_i != 1;
                            $alt_occ_flag = 'Y' if $occ_j != 1;
            
                            warn "$pdb_id has alt_occ_flag Y" if $alt_occ_flag;

                            if ( $sg_i->distance($sg_j) <= $ss_cutoff ) {
                                my $cys_cys_table = $CysDB->cys_cys_table(
                                    pdb_id       => $pdb_id,
                                    entity_idi   => $meta_i->{entity_id},
                                    entity_idj   => $meta_j->{entity_id},
                                    chain_idi    => $meta_i->{chain_id},
                                    chain_idj    => $meta_j->{chain_id},
                                    cys_conf_idi => $meta_i->{cys_conf_id},
                                    cys_conf_idj => $meta_j->{cys_conf_id},
                                    alt_id_sum   => $alt_id_sum,
                                    alt_occ_flag => $alt_occ_flag,
                                    cys_i        => $cys_i,
                                    cys_j        => $cys_j,
                                );
                                my $cys_cys_entry =
                                  $cys_cys_rs->find_or_new($cys_cys_table);
                                if ( $cys_cys_entry->in_storage ) {
                                    $ss_in_storage++;
                                }
                                else {
                                    $cys_cys_entry->insert;
                                    $ss_count++;
                                }
                            }
                        }
                    }

                }
            }
        }
        $date = strftime '%Y-%m-%d_%H:%M.%S', localtime();
        print $fh
"$date $pdb_id: loaded $ss_count into cys_cys; $ss_in_storage entries already stored\n";

    }
}

