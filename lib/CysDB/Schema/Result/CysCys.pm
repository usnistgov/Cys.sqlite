package CysDB::Schema::Result::CysCys;
use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('Cys_Cys');
__PACKAGE__->add_columns(
    id => {
        data_type         => 'integer',
        is_auto_increment => 1,
    },
    pdb_id => {
        data_type      => 'varchar',
        size           => '4',
        is_foreign_key => 1,
    },
    entity_idi => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    entity_idj => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    chain_idi => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    chain_idj => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    cys_conf_idi => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    cys_conf_idj => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    mol_code => {
        data_type => 'varchar',
    },
    alt_id_sum => { # 0, 1, 2
        data_type => 'integer',
    },
    SGi_SGj => {
        data_type => 'float',
    },
    CAi_CAj => {
        data_type => 'float',
    },
    CBi_SGi_SGj => {
        data_type => 'float',
    },
    SGi_SGj_CBj => {
        data_type => 'float',
    },
    CAi_CBi_SGi_SGj => {
        data_type => 'float',
    },
    CBi_SGi_SGj_CBj => {
        data_type => 'float',
    },
    SGi_SGj_CBj_CAj => {
        data_type => 'float',
    },
    dse => {
        data_type => 'float',
    },
    class => {
        data_type => 'varchar',
    },
    alt_occ_flag => { 
        # robust selection flag for partial occupancy
        # alt_id_sum ignores partial occ with null alt_id
        data_type   => 'varchar',
        size        => 1, # 'Y'
        is_nullable => 1, # 'Y'
    },
);

__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(
    'constraint_cyscys' => [qw/cys_conf_idi cys_conf_idj/], );

__PACKAGE__->belongs_to( 'cys_conf_i', 'CysDB::Schema::Result::CysConf',
    'cys_conf_idi' );
__PACKAGE__->belongs_to( 'cys_conf_j', 'CysDB::Schema::Result::CysConf',
    'cys_conf_idj' );
__PACKAGE__->belongs_to( 'chain_i', 'CysDB::Schema::Result::ChainCys',
    'chain_idi' );
__PACKAGE__->belongs_to( 'chain_j', 'CysDB::Schema::Result::ChainCys',
    'chain_idj' );
__PACKAGE__->belongs_to( 'entity_i', 'CysDB::Schema::Result::EntityCys',
    'entity_idi' );
__PACKAGE__->belongs_to( 'entity_j', 'CysDB::Schema::Result::EntityCys',
    'entity_idj' );
__PACKAGE__->belongs_to( 'pdb' => 'CysDB::Schema::Result::PDB', 'pdb_id' );

1;
