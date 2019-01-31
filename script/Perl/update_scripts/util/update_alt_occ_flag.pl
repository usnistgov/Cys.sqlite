# wrote this script to patch in the pdbx_entity_id which is useful for searching rcsb
use Modern::Perl;
use lib 'lib';
use CysDB;
use HackaMol;
use Data::Dumper;

die "you should not have to run this";
my $schema = CysDB->new()->schema;

my $ss_rs = $schema->resultset('CysCys')->search(
    {
        -or => {
            'cys_conf_i.SG_occ' => {'<',1},
            'cys_conf_j.SG_occ' => {'<',1},
            'cys_conf_i.alt_id' => \'IS NOT NULL',
            'cys_conf_j.alt_id' => \'IS NOT NULL',
        }
    },
    {
        join => ['cys_conf_i','cys_conf_j'],
        distinct => 1,
    }
);

$ss_rs->update({alt_occ_flag => 'Y'});


