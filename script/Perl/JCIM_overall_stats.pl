#!/usr/bin/env perl
# Description: generates overall counts of each table, LaTeX of Table 1 of the associated publication 
#
# count number of pdb, entity_cys, chain_cys, cys, cys_conf, and cys_cys for each experimental method
# (X-RAY DIFFRACTION, SOLUTION NMR, ELECTRON MICROSCOPY)
#
# add ID: none, 100, 50
#
use Modern::Perl;
use Path::Tiny;
use lib 'lib';
use CysDB;
use JSON::XS;
use POSIX qw(strftime);
use Scalar::Util qw(looks_like_number);

my $date   = strftime "%Y-%m-%d", localtime();
my $CysDB  = CysDB->new();
my $schema = $CysDB->schema;

# bin up the number of cys in cys table

my %exp;
my $count = 0;

my @meths = ( "X-RAY DIFFRACTION", "SOLUTION NMR", "ELECTRON MICROSCOPY" );
my %exp_count;
my %entity_SEEN;

#set up the result sets to count based on PDB attributes
my %prefetch_dp = (
    PDB       => undef,
    EntityCys => { join => { chain_cys => 'pdb' }, distinct => 1 },
    ChainCys => { join => 'pdb', distinct => 1 },
    Cys      => { join => 'pdb', distinct => 1 },
    CysConf  => { join => 'pdb', distinct => 1 },
    CysCys => { join => [ 'pdb', 'cys_conf_i' ], distinct => 1 },
);

my $pdb_obsol_count =
  $schema->resultset('PDB')->search( { status => "OBSOLETE" } )->count;

# accumulate information
foreach my $method (@meths) {

    # pull the resultsets
    foreach my $table ( keys %prefetch_dp ) {
        say "$method $table";
        my $pre      = $table =~ /PDB/ ? '' : 'pdb.';
        my $prefetch = $prefetch_dp{$table};
        my $rs       = $schema->resultset($table)->search(
            {
                "${pre}status" => "CURRENT"
            },
            $prefetch
        );

        # overall count with no exp_method filter
        my $total = $rs->count;
        $exp_count{All}{$table}{'TOTAL'} = $total;

        my $method_rs = $rs->search({"${pre}exp_method"=> $method});

        my $m_count = $method_rs->count;
        $exp_count{$method}{$table}{'NONE'} = $m_count;
        say "$method $table NONE $m_count";

        # only the first model as shortcut to unique entries for CysCys
        my $uniq_rs;
        if ($table eq 'CysCys'){
            $uniq_rs = $method_rs->search({ "cys_conf_i.model_num" => 1 });
            $exp_count{$method}{"$table.uniq"}{'NONE'} = $uniq_rs->count; 
        }

        foreach my $ident ('100', '50' ) {

            my $idm_rs = $method_rs->search(
                {
                    "${pre}exp_method_identity_cutoff" => $ident,
                },
            );
            my $idm_count = $idm_rs->count;
            
            $exp_count{$method}{$table}{$ident} = $idm_count;

            if($uniq_rs){
                $exp_count{$method}{"$table.uniq"}{$ident} = $uniq_rs->search({"${pre}exp_method_identity_cutoff" => $ident})->count ;
            }

            say "$method $table $ident $idm_count";

        }
    }
}

my $orphan_entities = 0;

ORPHANED_ENTITIES: {

    # generate resultset for unique entities that map to an obsolete pdb
    my $entity_cys_rs =
      $schema->resultset('EntityCys')->search( { 'pdb.status' => 'OBSOLETE' },
        { join => { 'chain_cys' => 'pdb' }, distinct => 1 } );

    my @orphans;

    # search for any of the above that do not hit a current PDB
    while ( my $entity = $entity_cys_rs->next ) {
        my $current_entity_cys_rs = $schema->resultset('EntityCys')->search(
            {
                'pdb.status' => 'CURRENT',
                'me.id'      => $entity->id,
            },
            { join => { 'chain_cys' => 'pdb' } }
        );

        push @orphans, $entity->sequence unless $current_entity_cys_rs->count;

    }
    $orphan_entities = scalar(@orphans);
}

my %short_names = (
    "X-RAY DIFFRACTION"   => 'X-ray',
    "SOLUTION NMR"        => 'NMR',
    "ELECTRON MICROSCOPY" => "EM",

);
say '\begin{table}[]';
say '\begin{tabular}{l|l|rrrr}';

say
"%see JCIM_figtab/tab1\_overall\_stats.pl; make sure the exp\_method\_identity has been recalculated (db_script/util/populate_exp_method_identity.pl)";
say "\\hline";
print join ' & ', ( "Table", "exp\\_method", qw(50 100 NONE) );
say " \\\\";
say "\\hline";

foreach my $table (qw/PDB EntityCys ChainCys Cys CysConf CysCys/) {
    print "\\multirow{4}{*}{$table}\n";
    foreach my $meth (@meths) {
        my @ids = map { $exp_count{$meth}{$table}{$_} } qw/50 100 NONE/;

        # 100 = 50 + 100 selection
        $ids[1] += $ids[0];
        my @uids;
        my $short = $short_names{$meth};
      UNIQ: {
          if ( $meth =~ /NMR/ && $table =~ /CysCys/ ) {
                my @uids =
                  map { $exp_count{$meth}{"$table.uniq"}{$_} } qw/50 100 NONE/;
                $uids[1] += $uids[0];
                my @comb = map { "$ids[$_]($uids[$_])" } 0 .. $#uids;
                print "& ", join ' & ', ( $short, @comb );
            }
            else {
                print "& ", join ' & ', ( $short, @ids );
            }
        }

        say " \\\\";
    }
    print "& All & & & ", $exp_count{All}{$table}{TOTAL};
    say " \\\\";
    say "\\hline";
}

my $string =
"\\caption{Summary of Cys.sqlite contents corresponding to current, released PDB entries (query run on $date). The counts 
are determined by method and sequence identity cutoff. Obsolete entries ($pdb_obsol_count) are not included; the 
$orphan_entities \\emph{Entity\\_Cys} entries with no current PDB entries are also ignored. For each value 
of the sequence identity cutoff (50 100 NONE), the count represents the total in that set. The \\emph{Cys\\_Cys} table 
includes both the total and unique disulfides, in parenthesis, for NMR. The \\emph{Entity\\_Cys} values are 
determined using a join on the \\emph{Chain\\_Cys} and \\emph{PDB} tables.}";
$string =~ s/\n/ /g;
say $string;
say '\label{tab:overall}';
say '\end{tabular}';
say '\end{table}';
