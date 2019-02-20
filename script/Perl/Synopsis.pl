use Modern::Perl;
use lib 'lib';
use CysDB;

my $CysDB  = CysDB->new();                                      # create instance of CysDB class
my $schema = $CysDB->schema;                                    # connect and grab the schema  (Cys.sqlite is in workind directory)

my @pdb_ids = $schema->resultset('PDB')                         # DBIX::Class  resultset for PDB table
                     ->search( undef, { columns => ['id'] } )   # select id from PDB
                     ->get_column('id')                         # get column of ids
                     ->all;                                     # send the list to the @pdb_ids array variable

say foreach @pdb_ids;

