use Modern::Perl;
use Path::Tiny;
use POSIX qw(strftime);
use JSON::PP;
use lib 'lib';
use HackaMol;
use Data::Dumper;
use CysDB;

#die "run this as much as you want! but it will take a long time to sync an empty dir";
my $CysDB = CysDB->new();

# fetch all rcsb_pdbids using ss query
my @pdbids = $CysDB->fetch_rcsb_pdbids; 

my $bldr = HackaMol->new();
my ($synced_pdbids, $missed_pdbids) = $bldr->rcsb_sync_local('cif', @pdbids);

print Dumper $missed_pdbids;

my $date = strftime '%Y-%m-%d', localtime();

my $db_loads_path = path("db_loads");
#add incrementing postfix on date in filename if exists 
my $i = 0;
while ($db_loads_path->children(qr/$date\w+_$i\.json/)){
    $i++;
}
$db_loads_path->child("${date}_synced_$i.json")->spew(JSON::PP->new()->pretty->canonical->encode($synced_pdbids));
$db_loads_path->child("${date}_missed_$i.json")->spew(JSON::PP->new()->pretty->canonical->encode($missed_pdbids));

