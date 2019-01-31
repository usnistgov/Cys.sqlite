# use this script to add pdbs that may not show up in the disulfide search.
use Modern::Perl;
use Path::Tiny;
use JSON::PP;
use lib 'lib';
use CysDB;

# pdbs from x-ray-induced deterioration of disulfide bridges at atomic resolution
#Petrova et al
# many of these do not resolve via the REST rcsb search >= 1 ss bond
#Acta Cryst. (2010). D66, 1075-1091
#https://doi.org/10.1107/S0907444910033986
my @acta_D_2010_pdb_ids = (
    qw/3mnb 3mnc 3mns 3mnx 3mo3 3mo6 3mo9 3moc 3mty 3odf 3mu0 3mu1 3mu4 3odd 3mu5 3mu8/
);

# generate the json file for those not in Cys.sqlite
my $CysDB  = CysDB->new();
my $pdb_rs = $CysDB->schema->resultset('PDB');
my $file_name = "db_loads/2010_petrova_actaD.json";

my @missing_pdbs;
foreach my $pdb_id (@acta_D_2010_pdb_ids) {
    if ( $pdb_rs->find( uc($pdb_id) ) ) {
        warn "found $pdb_id in cys.sqlite, skipping sync";
    }
    else {
        push @missing_pdbs, uc($pdb_id);
    }
}

if (@missing_pdbs){

    print "PDB_ids written to $file_name\n";
    path($file_name)
        ->spew( JSON::PP->new()->pretty->canonical->encode( \@missing_pdbs ) );
    print "perl db_script/SYNC_and_LOAD.pl $file_name\n";
}
else{
    print "nothing was missing"
}
