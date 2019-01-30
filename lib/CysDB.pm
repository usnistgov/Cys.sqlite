package CysDB;
use Moose;
use MooseX::Types::Path::Tiny qw/Path Paths AbsPath AbsPaths/;
use Modern::Perl;
use Mojo::UserAgent;
use Path::Tiny;
use CysDB::Schema;
use XML::Twig;
use XML::Generator;

with 'CysDB::Roles::HM';

use Moose::Util::TypeConstraints;

has 'schema' => (
    isa => 'DBIx::Class::Schema',
    is         => 'ro',
    builder    => '_connect_schema',
    lazy       => 1 
);

has 'sqlite_path' => (
    is      => 'ro',
    isa     => Path,
    coerce  => 1,
    default => 'cys.sqlite',
    lazy => 1,
);

sub _connect_schema {
    my $self = shift;
    my $sqlite_path = $self->sqlite_path->stringify;
    return CysDB::Schema->connect("dbi:SQLite:$sqlite_path");
}

has 'rcsb_entity_map' => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef[Any]',
    default => sub { {} },
    handles => {
        set_entity_map    => 'set',
        get_entity_map    => 'get',
        exists_entity_map => 'exists',
    },
);

has 'rcsb_rest_addr' => (
    is      => 'ro',
    isa     => 'Str',
    default => 'http://www.rcsb.org/pdb/rest',
);

has 'rcsb_ss_query' => (
    is      => 'rw',
    isa     => 'Str',
    builder => '_rcsb_ss_query',
);

has 'query_ss' => (
    is        => 'rw',
    isa       => 'Bool',
    default   => 1,
    predicate => 'has_query_SS',
);

has 'query_identityCutoff' => (
    is      => 'rw',
    default => undef,
    clearer => 'clear_query_identityCutoff',
);

enum expMethod => [
    'X-RAY',
    'X-RAY DIFFRACTION',
    'POWDER DIFFRACTION',
    'NEUTRON',
    'NEUTRON DIFFRACTION; X-RAY DIFFRACTION',
    'X-RAY DIFFRACTION; NEUTRON DIFFRACTION',
    'SOLUTION NMR',
    'SOLID-STATE NMR',
    'INFRARED SPECTROSCOPY',
    'ELECTRON MICROSCOPY',
    'ELECTRON CRYSTALLOGRAPHY',
    'FIBER DIFFRACTION',
    'NEUTRON DIFFRACTION',
    'SOLUTION SCATTERING',
    'OTHER',
    'HYBRID'
];
has 'query_expMethod' => (
    is        => 'rw',
    isa       => 'expMethod',
    default   => 'X-RAY',
    predicate => 'has_query_expMethod',
);

sub update_obsolete {
    my $self = shift;
    my $pdb_rs       = $self->schema->resultset('PDB');
    my @pdbids_src   = $pdb_rs->get_column('id')->all;
    my %all_obsolete = map {$_ => 1} $self->get_rcsb_obsolete;
    my @obsolete     = grep { $all_obsolete{$_} } @pdbids_src;

    foreach my $obs_id (@obsolete) {
        $pdb_rs->find($obs_id)->update(
        {
            status                     => 'OBSOLETE',
            exp_method_identity_cutoff => undef
        }
    );
    }
    return @obsolete;
}

sub get_rcsb_obsolete {

    my $self = shift;
    #fetch all obsolete pdbids from rcsb 
    my $ua = Mojo::UserAgent->new();


    # you can get current "https://www.rcsb.org/pdb/rest/getCurrent" ( on order of 150 K vs 5 K for obsolete)
    my $url  = $self->rcsb_rest_addr . "/getObsolete";
    my $xml = $ua->get($url)->result->body;

    my $t = XML::Twig->new();
    $t->parse($xml);

    my $root = $t->root;

    my @pdb_ids;
    foreach my $pdb ($root->children('PDB')){
        push @pdb_ids, $pdb->att('structureId');
    }

    return @pdb_ids;
}


sub get_pdbid_rcsb_describePDB {

    my $self  = shift;
    my $pdbid = shift;
    my $ua    = Mojo::UserAgent->new;

    my $xml =
      $ua->get("https://www.rcsb.org/pdb/rest/describePDB?structureId=$pdbid")
      ->result->body;

    my $t = XML::Twig->new();
    $t->parse($xml);

    my $pdb = $t->root->first_child('PDB');

    my @attrs =
      qw/structureId resolution deposition_date nr_residues nr_entities
      largeStructure expMethod keywords status/;

    my %res = map { $_ => $pdb->att($_) } @attrs;
    return \%res;

}

=method fetch_rcsb_pdbids

uses the Mojo::UserAgent to post $self->rcsb_ss_query to $self->rcsb_rest_addr

returns @pdbids

=cut

sub fetch_rcsb_pdbids {
    my $self  = shift;
    my $ua    = Mojo::UserAgent->new;
    my $url   = $self->rcsb_rest_addr . "/search" ;
    my $query = shift || $self->rcsb_ss_query;
    my $tx    = $ua->post( $url,
        { 'Content-Type' => 'application/x-www-form-urlencoded' }, $query );
    my @pdbids;
    if ( my $res = $tx->success ) {
        @pdbids = map { lc } split /\n/, $res->body;
    }
    else {
        my $err = $tx->error;
        die "$err->{code} response: $err->{message}" if $err->{code};
        die "Connection error: $err->{message}";
    }
    return @pdbids;
}

sub get_pdbids_rcsb_fasta {
    my $self = shift;
    my $pdbids = join( ',', @_ );

    print $pdbids;
    my $ua  = Mojo::UserAgent->new;
    my $url = "https://www.rcsb.org/pdb/download/";
    my $param =
      "viewFastaFiles.do?structureIdList=$pdbids&compressionType=uncompressed";
    my $fasta = $ua->get( $url . $param )->result->body;
    return $fasta;
}

sub build_xml_query {
    my $xml = XML::Generator->new(':pretty');

    my $self = shift;

    my $i       = 0;
    my @refines = ();

    if ( $self->has_query_SS ) {
        push @refines, (
            $xml->queryRefinement(
                $xml->queryRefinementLevel( $i++ ),
                $xml->orgPdbQuery(
                    $xml->version("head"),
                    $xml->queryType("org.pdb.query.simple.CloseContactsQuery"),
                    $xml->description("records with ss links: min 1"),
                    $xml->min(1)
                )
              )

        );
    }

    if ( $self->has_query_expMethod ) {
        my $method_leaf = 'mvStructure.expMethod.value';
        push @refines,
          (
            $xml->queryRefinement(
                $xml->queryRefinementLevel( $i++ ),
                $xml->conjunctionType('and'),
                $xml->orgPdbQuery(
                    $xml->version("head"),
                    $xml->queryType('org.pdb.query.simple.ExpTypeQuery'),
                    $xml->$method_leaf( $self->query_expMethod )
                )
            )
          );
    }

    if ( $self->query_identityCutoff ) {
        push @refines,
          (
            $xml->queryRefinement(
                $xml->queryRefinementLevel( $i++ ),
                $xml->conjunctionType('and'),
                $xml->orgPdbQuery(
                    $xml->version("head"),
                    $xml->queryType(
                        'org.pdb.query.simple.HomologueReductionQuery'),
                    $xml->identityCutoff( $self->query_identityCutoff )
                )
            )
          );
    }

    return (
        sprintf( "%s",
            $xml->orgPdbCompositeQuery( { version => '1.0' }, @refines ) )
    );
}

sub _rcsb_ss_query {
    my $xml = XML::Generator->new(':pretty');
    return (
        sprintf(
            "%s",
            $xml->orgPdbCompositeQuery(
                { version => "1.0" },
                $xml->queryRefinement(
                    $xml->queryRefinementLevel(0),
                    $xml->orgPdbQuery(
                        $xml->version("head"),
                        $xml->queryType(
                            "org.pdb.query.simple.CloseContactsQuery"),
                        $xml->description("records with ss links: min 1"),
                        $xml->min(1)
                    )
                )
            )
        )
    );
}

sub build_xml_composite_query {
    my $self    = shift;
    my @refines = @_;
    my $xml     = XML::Generator->new(':pretty');
    my $i       = 0;

    my @q_res = (
        $xml->queryRefinement(
            $xml->queryRefinementLevel( $i++ ),
            shift @refines
        )
    );
    push @q_res,
      (
        $xml->queryRefinement(
            $xml->queryRefinementLevel( $i++ ), $xml->conjunctionType('and'),
            $_,
        )
      ) foreach @refines;
    return $xml->orgPdbCompositeQuery( { version => "1.0" }, @q_res );
}

sub build_xml_blast_query {
    my $self   = shift;
    my $target = shift
      || die "need target that has sequence [ pdb_id, chain_id ]";
    my $ecutoff       = shift || 10;
    my $seq_id_cutoff = shift || 0;
    my $tool          = shift || 'blast';

    my $pdb_id   = $target->{pdb_id};
    my $chain_id = $target->{chain_id};
    my $seq      = $target->{sequence};

    warn "no chain id passed"    unless $chain_id;
    warn "no pdb id passed"      unless $pdb_id;
    warn "no sequence id passed" unless $seq;

    my $xml = XML::Generator->new(':pretty');

    my @els;
    push @els, $xml->sequence($seq)       if ($seq);
    push @els, $xml->chainId($chain_id)   if ($chain_id);
    push @els, $xml->structureId($pdb_id) if ($pdb_id);

    die "no elements to blast against" unless @els;

    return (
        $xml->orgPdbQuery(
            $xml->version("head"),
            $xml->queryType("org.pdb.query.simple.SequenceQuery"),
            @els,
            $xml->searchTool($tool),
            $xml->maskLowComplexity('yes'),
            $xml->eValueCutoff($ecutoff),
            $xml->sequenceIdentityCutoff($seq_id_cutoff),
        )
    );
}

sub build_xml_resolution_query {
    my $self    = shift;
    my $min_res = shift || die "initial resolution";
    my $max_res = shift || die "final   resolution";

    my $xml        = XML::Generator->new(':pretty');
    my $comparator = 'refine.ls_d_res_high.comparator';
    my $min        = 'refine.ls_d_res_high.min';
    my $max        = 'refine.ls_d_res_high.max';
    return (
        $xml->orgPdbQuery(
            $xml->version("head"),
            $xml->queryType("org.pdb.query.simple.ResolutionQuery"),
            $xml->$comparator('between'),
            $xml->$min($min_res),
            $xml->$max($max_res),
        )
    );

}

sub build_xml_identity_cutoff_query {
    my $self = shift;
    my $identity_cutoff = shift || die "sequence_identity cutoff";

    my $xml = XML::Generator->new(':pretty');
    return (
        $xml->orgPdbQuery(
            $xml->version("head"),
            $xml->queryType(
                "org.pdb.query.simple.HomologueEntityReductionQuery"),
            $xml->identityCutoff($identity_cutoff),
        )
    );

}

1;
