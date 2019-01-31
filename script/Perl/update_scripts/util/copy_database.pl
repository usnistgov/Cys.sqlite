use Modern::Perl;
use Path::Tiny;
#
# useful for minor changes, like column types
#
use lib 'lib';
use CysDB;
use Data::Dumper;


my $source = shift || die "pass path to cys.sqlite file with source of information\n";
my $target = shift || die "pass path where new cys.sqlite file will be written (cannot exist)\n";

die "$source does not exist" if ! -e $source;
die "$target exists" if -e $target;

my $source_path = path($source);
my $target_path = path($target);

my $source_schema =
  CysDB::Schema->connect( "dbi:SQLite:" . $source_path->stringify ); # for big schema changes, CysDB::Schema should be the old schema

my $target_schema =
  CysDB::Schema->connect( "dbi:SQLite:" . $target_path->stringify );

$target_schema->deploy;

my @tables = qw(PDB EntityCys ChainCys Cys CysConf CysCys);


foreach my $table (@tables) {
    say $table;
    my $src_rs      = $source_schema->resultset($table);
    my $trg_rs      = $target_schema->resultset($table);
    $src_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    $trg_rs->populate( [$src_rs->all] );
}


