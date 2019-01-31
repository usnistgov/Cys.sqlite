use Modern::Perl;
use Path::Tiny;
use lib 'lib';
use CysDB;

my $N = shift;
if ( !$N ) {
    warn "optional argument: number of top PDB entities (default 10)\n";
    $N = 10;
}

my $schema = CysDB->new()->schema;

my $chain_rs = $schema->resultset('ChainCys')->search(
    { 'pdb.status' => 'CURRENT' },
    {
        join     => 'pdb',
        columns  => [ 'pdb_id', 'entity_id' ],
        distinct => 1,
    }
);

$chain_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');

say 'ChainCys entry count:', $chain_rs->count;

# array of hashes keys: pdb_id and entity_id
my @entries = $chain_rs->all;

my %entity_pdbid_count;
foreach my $entry (@entries) {
    $entity_pdbid_count{ $entry->{entity_id} }++;
}

my @sorted_entities =
  sort { $entity_pdbid_count{$b} <=> $entity_pdbid_count{$a} }
  keys %entity_pdbid_count;

say 'number of entities: ', scalar(@sorted_entities);
my $sum = 0;
$sum += $_ foreach values %entity_pdbid_count;
say 'chaincys sanity check: ', $sum;

my $cys_cys_rs = $schema->resultset('CysCys');

my $running_sum = 0;
foreach my $entity_id ( @sorted_entities[ 0 .. $N - 1 ] ) {
    my $cys_cys_count = $cys_cys_rs->search(
        [
            -or => {
                entity_idi => $entity_id,
                entity_idj => $entity_id,
            }
        ]
    )->count;

    $running_sum += $cys_cys_count;

    printf(
        "%-8i %4i %4i %5i %.2f\n",
        $entity_id, $entity_pdbid_count{$entity_id},
        $cys_cys_count, $running_sum, $cys_cys_count/$entity_pdbid_count{$entity_id}
    );

}

exit;
