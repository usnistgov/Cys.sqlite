# wrote this script to patch in the pdbx_entity_id which is useful for searching rcsb
use Modern::Perl;
use lib 'lib';
use CysDB;
use HackaMol;
use Data::Dumper;

my $schema = CysDB->new()->schema;
my $bldr = HackaMol->new();

my $pdb_rs = $schema->resultset('PDB');#->search({id => '12E8'});

while(my $pdb = $pdb_rs->next){
    say $pdb->id;
    my $cif = $bldr->pdbid_local_path($pdb->id,'cif');
    my $fh = $cif->openr_raw;
    my $info = $bldr->read_cif_info($fh);
    my $entity = $info->{entity};

    # create sequence -> id map
    my %seq_pdbx_entity_id;
    foreach my $pdbx_entity_id (keys %{$entity}){
        my $seq = $entity->{$pdbx_entity_id}{'_entity_poly.pdbx_seq_one_letter_code_can'};
        $seq_pdbx_entity_id{$seq} = $pdbx_entity_id;
    }

    foreach my $chain_cys ($pdb->chain_cys){
        my $entity_cys = $chain_cys->entity;
        die "sequence doesn't exist" unless exists($seq_pdbx_entity_id{ $entity_cys->sequence });
        my $pdbx_entity_id = $seq_pdbx_entity_id{ $entity_cys->sequence };
        $chain_cys->update({pdbx_entity_id => $pdbx_entity_id})
    }
    
    
}


