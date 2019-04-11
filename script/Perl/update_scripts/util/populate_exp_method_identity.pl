# builds the sets of ids using RCSB xml queries 
use Modern::Perl;
use Path::Tiny;
use lib 'lib';
use CysDB;

my $schema = CysDB->new()->schema;

my $pdb_rs = $schema->resultset('PDB')->search({status => 'CURRENT'});
my @pdbids = $pdb_rs->get_column('id')->all;

my %seen = map { $_ => 1 } @pdbids;
my @methods = ('X-RAY DIFFRACTION', 'SOLUTION NMR','ELECTRON MICROSCOPY');

my @cutoffs = (100,50); 

# carry out the rcsb query 
my ($sets,$queries) = fetch_query(\@methods, \@cutoffs);

die "sets are undefined" unless $sets;

# accumulate pdb_id -> cutoff info
#   carry out a few neurotic tests that have never failed 
my %exp_ident;
my %missing_overlap;
foreach my $exp_method ( keys %{ $sets } ){
    #test for coverage
    my @sames = @{$sets->{$exp_method}{100}};
    my @halfs = @{$sets->{$exp_method}{50}};

    die "clobber via $exp_method ?" if grep {exists($exp_ident{$_})} @sames;

    $exp_ident{$_} = 100 foreach @sames;

    foreach my $pdbid (@halfs){
        unless (exists ($exp_ident{$pdbid})){
            push @{$missing_overlap{$exp_method}}, $pdbid;
        }
        $exp_ident{$pdbid} = 50 ;
    }
}

if (keys %missing_overlap){
    use Data::Dumper;
    warn "RCSB may have changed. Found PDB_IDs in the 50% group that are not in the 100% group:";
    print Dumper {"Queries: " => $queries };
    print Dumper {"50 not in 100" => \%missing_overlap};
}

# clear out identity cutoffs
$pdb_rs->update_all({exp_method_identity_cutoff => undef});


foreach my $pdbid (keys %exp_ident){
    my $ident = $exp_ident{$pdbid};
    $pdb_rs->find({id => uc($pdbid)})->update({exp_method_identity_cutoff => $ident});
}

sub fetch_query{

    my $methods = shift;
    my $cutoffs = shift;

    my %sets;

    my @queries;
    foreach my $expMethod(@$methods){
        foreach my $cutoff (@$cutoffs){
            my $cysdb = CysDB->new(query_expMethod => $expMethod, query_identityCutoff => $cutoff);
            my $query = $cysdb->build_xml_query();
            push @queries, $query;
            my @pdbids = $cysdb->fetch_rcsb_pdbids($query);
            say "$expMethod $cutoff from RCSB: ", scalar(@pdbids), 
                " in cys.sqlite: ", scalar( grep { exists($seen{uc($_)}) } @pdbids);
            $sets{$expMethod}{$cutoff} = \@pdbids;
        }
    }
    return \%sets, \@queries;
}


