use Modern::Perl;
use lib 'lib';
use CysDB;
use Test::More;

my $CysDB = CysDB->new();

my @pdb_ids = $CysDB->schema->resultset('PDB')                         
                     ->search( undef, { columns => ['id'] } )   
                     ->get_column('id')                         
                     ->all;                                     
is_deeply([$CysDB->check_pdbids(\@pdb_ids)], [], 'check_pdbids against self returns empty array');

done_testing();
