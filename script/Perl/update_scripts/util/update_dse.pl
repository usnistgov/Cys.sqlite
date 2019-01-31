# wrote this script to patch in the pdbx_entity_id which is useful for searching rcsb
use Modern::Perl;
use lib 'lib';
use Math::Trig;
use CysDB;
use HackaMol;
use Data::Dumper;

die "you should not have to run this; adjust if you wish to change the dse model";
my $schema = CysDB->new()->schema;

my $cys_cys_rs = $schema->resultset('CysCys')->search(
    {},
    {
        join => ['cys_conf_i', 'cys_conf_j'],
        columns => [
            'me.id',
            'me.pdb_id','me.DSE',
            'me.CAi_CBi_SGi_SGj', 'me.CBi_SGi_SGj_CBj', 'me.SGi_SGj_CBj_CAj',
        ],
        '+select' => ['cys_conf_i.N_CA_CB_SG','cys_conf_j.N_CA_CB_SG'],
        '+as'     => ['Ni_CAi_CBi_SGi','Nj_CAj_CBj_SGj'],
    }
);


while ( my $ss = $cys_cys_rs->next ){
    my %hash  = $ss->get_columns;
    my $chi1  = $hash{'Ni_CAi_CBi_SGi'};
    my $chi2  = $hash{'CAi_CBi_SGi_SGj'};
    my $chi3  = $hash{'CBi_SGi_SGj_CBj'};
    my $chi2p = $hash{'SGi_SGj_CBj_CAj'};
    my $chi1p = $hash{'Nj_CAj_CBj_SGj'};

    my $dse1 =
      2.0 * ( 1 + cos( 3 * deg2rad($chi1) ) ) +   # 1.4 in AMBER
      2.0 * ( 1 + cos( 3 * deg2rad($chi1p) ) ) ;  # 1.4 in AMBER

    my $dse2 =
      1.0 * ( 1 + cos( 3 * deg2rad($chi2) ) ) +
      1.0 * ( 1 + cos( 3 * deg2rad($chi2p) ) ) ;

    my $dse3 = 3.5 * ( 1 + cos( 2 * deg2rad($chi3) ) ) +
      0.6 * ( 1 + cos( 3 * deg2rad($chi3) ) );

    my $dse = 4.184*($dse1+$dse2+$dse3);

    $ss->update({dse => $dse});
    printf ("%4s %8.1f %8.1f\n", $hash{pdb_id}, $dse, $hash{DSE}); 
}

