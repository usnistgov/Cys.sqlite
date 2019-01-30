package CysDB::Schema::Result::Cys;
use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('Cys');
__PACKAGE__->add_columns(
    id => {
        data_type   => 'INTEGER',
        is_nullable => 0,
    },
    chain_id => {
        data_type      => 'INTEGER',
        is_nullable    => 0,
        is_foreign_key => 1,
    },
    entity_id => {
        data_type      => 'INTEGER',
        is_nullable    => 0,
        is_foreign_key => 1,
    },
    pdb_id => {
        data_type      => 'varchar',
        size           => '4',
        is_nullable    => 0,
        is_foreign_key => 1,
    },
    seq_id => {
        data_type   => 'varchar',    # usually integer but not always
        is_nullable => 0,
    },
    auth_seq_id => {
        data_type   => 'varchar',    # usually integer but not always
        is_nullable => 1,
    },
    insert_code => {
        data_type   => 'varchar',
        is_nullable => 1,
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(
    'constraint_cys' => [qw/chain_id seq_id/], );
__PACKAGE__->belongs_to(
    'entity' => 'CysDB::Schema::Result::EntityCys',
    'entity_id'
);
__PACKAGE__->belongs_to( 'pdb' => 'CysDB::Schema::Result::PDB', 'pdb_id' );
__PACKAGE__->belongs_to(
    'chain' => 'CysDB::Schema::Result::ChainCys',
    'chain_id'
);

__PACKAGE__->has_many( 'cys_conf', 'CysDB::Schema::Result::CysConf', 'cys_id',
);

1;
