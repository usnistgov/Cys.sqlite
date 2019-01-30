package CysDB::Schema::Result::ChainCys;
use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('Chain_Cys');
__PACKAGE__->add_columns(
    id => {
        data_type   => 'INTEGER',
        is_nullable => 0,
    },
    pdb_id => {
        data_type      => 'varchar',
        size           => '4',
        is_nullable    => 0,
        is_foreign_key => 1,
    },
    entity_id => {
        data_type      => 'INTEGER',
        is_nullable    => 0,
        is_foreign_key => 1,
    },
    pdbx_entity_id => {
        data_type      => 'INTEGER',
        is_nullable    => 0,
    },
    asym_id => {
        data_type => 'varchar',
        size      => 2,
    },
    auth_asym_id => {
        data_type => 'varchar',
        size      => 2,
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint( 'constraint_chain' => [qw/pdb_id asym_id/],
);
__PACKAGE__->belongs_to( 'pdb' => 'CysDB::Schema::Result::PDB', 'pdb_id' );
__PACKAGE__->belongs_to(
    'entity' => 'CysDB::Schema::Result::EntityCys',
    'entity_id'
);
__PACKAGE__->has_many( 'cys', 'CysDB::Schema::Result::Cys', 'chain_id', );
__PACKAGE__->has_many( 'cys_conf', 'CysDB::Schema::Result::CysConf',
    'chain_id', );
__PACKAGE__->has_many( 'cys_cys_i', 'CysDB::Schema::Result::CysCys',
    'chain_idi', );
__PACKAGE__->has_many( 'cys_cys_j', 'CysDB::Schema::Result::CysCys',
    'chain_idj', );

1;
