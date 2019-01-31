use Modern::Perl;
use lib 'lib';
use CysDB;


CysDB->new()->schema->resultset('PDB')->update({status => 'CURRENT'});

