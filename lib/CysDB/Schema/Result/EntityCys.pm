package CysDB::Schema::Result::EntityCys;
use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('EntityCys');
__PACKAGE__->add_columns(
    "id",
    {
        data_type   => 'INTEGER',
        is_nullable => 0,
    },
    sequence => {
        data_type   => 'varchar',
        is_nullable => 0,
    },
    res_count => {
        data_type => 'integer',
    },
    cys_count => {
        data_type => 'integer',
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint( 'constraint_entity' => [qw/sequence/], );

__PACKAGE__->has_many( 'chain_cys', 'CysDB::Schema::Result::ChainCys',
    'entity_id', );
__PACKAGE__->has_many( 'cys', 'CysDB::Schema::Result::Cys', 'entity_id', );
__PACKAGE__->has_many( 'cys_conf', 'CysDB::Schema::Result::CysConf',
    'entity_id', );
__PACKAGE__->has_many( 'cys_cys_i', 'CysDB::Schema::Result::CysCys',
    'entity_idi', );
__PACKAGE__->has_many( 'cys_cys_j', 'CysDB::Schema::Result::CysCys',
    'entity_idj', );

1;

