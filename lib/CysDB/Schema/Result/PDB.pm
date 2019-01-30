package CysDB::Schema::Result::PDB;
use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('PDB');
__PACKAGE__->add_columns(
    id => {
        data_type => 'varchar',
        size      => '4',
    },
    exp_method => {
        data_type => 'varchar',
    },
    resolution => {
        data_type   => 'float',
        is_nullable => 1,
    },
    'chain_count' => {
        data_type   => 'integer',
        is_nullable => 1,
    },
    'cys_count' => {
        data_type   => 'integer',
        is_nullable => 1,
    },
    'res_count' => {
        data_type   => 'integer',
        is_nullable => 1,
    },
    keywords => {
        data_type => 'varchar',
    },
    deposition_date => {
        data_type => 'varchar',
    },
    last_revision_date => {
        data_type   => 'varchar',
        is_nullable => 1,
    },
    exp_method_identity_cutoff => {
        data_type   => 'varchar',
        is_nullable => 1,
    },
    status => {
        data_type   => 'varchar',
        is_nullable => 1,
    },

);

__PACKAGE__->set_primary_key('id');

__PACKAGE__->has_many( 'chain_cys', 'CysDB::Schema::Result::ChainCys',
    'pdb_id', );
__PACKAGE__->has_many( 'cys', 'CysDB::Schema::Result::Cys', 'pdb_id', );
__PACKAGE__->has_many( 'cys_conf', 'CysDB::Schema::Result::CysConf', 'pdb_id',
);
__PACKAGE__->has_many( 'cys_cys', 'CysDB::Schema::Result::CysCys', 'pdb_id', );

1;

