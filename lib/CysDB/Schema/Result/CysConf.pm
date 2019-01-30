package CysDB::Schema::Result::CysConf;
use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table('Cys_Conf');
__PACKAGE__->add_columns(
    id => {
        data_type         => 'INTEGER',
        is_auto_increment => 1,
    },
    cys_id => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    chain_id => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    entity_id => {
        data_type      => 'INTEGER',
        is_foreign_key => 1,
    },
    pdb_id => {
        data_type      => 'varchar',
        size           => '4',
        is_foreign_key => 1,
    },
    model_num => {
        data_type   => 'integer',
        is_nullable => 1,
    },
    alt_id => {
        data_type   => 'varchar',
        is_nullable => 1,
    },
    CA_bfact => {
        data_type => 'float',
    },
    SG_serial => {
        data_type   => 'integer',
        is_nullable => 0,
    },
    SG_occ => {
        data_type => 'float',
    },
    SG_bond_count => {
        data_type => 'integer',
    },
    omega => {
        data_type   => 'float',
        is_nullable => 1,
    },
    phi => {
        data_type   => 'float',
        is_nullable => 1,
    },
    psi => {
        data_type   => 'float',
        is_nullable => 1,
    },
    O_C_CA_CB => {
        data_type => 'float',
    },
    C_CA_CB => {
        data_type => 'float',
    },
    CA_CB => {
        data_type => 'float',
    },
    N_CA_CB_SG => {
        data_type => 'float',
    },
    CA_CB_SG => {
        data_type => 'float',
    },
    CB_SG => {
        data_type => 'float',
    },
    N_x => {
        data_type => 'float',
    },
    N_y => {
        data_type => 'float',
    },
    N_z => {
        data_type => 'float',
    },
    CA_x => {
        data_type => 'float',
    },
    CA_y => {
        data_type => 'float',
    },
    CA_z => {
        data_type => 'float',
    },
    C_x => {
        data_type => 'float',
    },
    C_y => {
        data_type => 'float',
    },
    C_z => {
        data_type => 'float',
    },
    O_x => {
        data_type => 'float',
    },
    O_y => {
        data_type => 'float',
    },
    O_z => {
        data_type => 'float',
    },
);

__PACKAGE__->set_primary_key('id');
# see 3ago for an SG without altloc paired with res with altloc
__PACKAGE__->add_unique_constraint(
    'constraint_cysconf_serial_modelnum' => [qw/pdb_id model_num alt_id SG_serial/], );
__PACKAGE__->add_unique_constraint(
    'constraint_cysconf' => [qw/cys_id model_num alt_id/], );
__PACKAGE__->belongs_to( 'cys', 'CysDB::Schema::Result::Cys', 'cys_id' );
__PACKAGE__->belongs_to( 'chain_cys', 'CysDB::Schema::Result::ChainCys',
    'chain_id' );
__PACKAGE__->belongs_to( 'pdb', 'CysDB::Schema::Result::PDB', 'pdb_id' );
__PACKAGE__->belongs_to( 'entity', 'CysDB::Schema::Result::EntityCys',
    'entity_id' );
__PACKAGE__->might_have(    # has_one ... might_have  ...
    'cys_cys_i', 'CysDB::Schema::Result::CysCys', 'cys_conf_idi',
);
__PACKAGE__->might_have(    # has_one ... might_have  ...
    'cys_cys_j', 'CysDB::Schema::Result::CysCys', 'cys_conf_idj',
);

1;
