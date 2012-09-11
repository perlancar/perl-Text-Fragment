package Text::Fragment;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Data::Clone;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(insert_fragment delete_fragment);

# VERSION

our %SPEC;

sub _label {
    my %args  = @_;
    my $id            = $args{id} // "";
    my $label         = $args{label};
    my $comment_style = $args{comment_style};
    my $attrs         = $args{attrs} // {};
    for (keys %$attrs) {
        /\A\w+\z/ or die "Invalid attribute name '$_', please use ".
            "letters/numbers only";
        $_ eq 'id' and die "Invalid attribute name '$_', reserved'";
    }

    my $attrs_re = qr/(?:\w+=\S+\s+)*id=\Q$id\E(?:\s+\w+=\S+)*/;
    my ($ts, $te); # tag start and end
    if ($comment_style eq 'shell') {
        $ts = "#";
        $te = "";
    } elsif ($comment_style eq 'c') {
        $ts = "/*";
        $te = "*/";
    } elsif ($comment_style eq 'cpp') {
        $ts = "//";
        $te = "";
    } elsif ($comment_style eq 'html') {
        $ts = "<!--";
        $te = "-->";
    } elsif ($comment_style eq 'ini') {
        $ts = ";";
        $te = "";
    } else {
        die "BUG: unknown comment_style $comment_style";
    }
    # regex to detect fragment
    my $ore = qr!^(.*?)\s*
                 \Q$ts\E\s*\Q$label\E\s+$attrs_re\s*\Q$te\E\s*(?:\R??|\z)!mx;
    my $mre = qr!^\Q$ts\E\s*BEGIN\s+\Q$label\E\s+$attrs_re\s*\Q$te\E\s*\R
                 (.*?)
                 ^\Q$ts\E\s*END  \s+\Q$label\E\s+$attrs_re\s*\Q$te\E
                 \s*(?:\R??|\z)!msx;

    return {
        one_line_comment   => " $ts $label id=$id" . ($te ? " $te":""),
        begin_comment      => "$ts BEGIN $label id=$id" . ($te ? " $te":""),
        end_comment        => "$ts END $label id=$id" . ($te ? " $te":""),
        one_line_pattern   => $ore,
        multi_line_pattern => $mre,
    };
}

sub _insert_or_delete_fragment {
    my ($which, %args) = @_;

    die "BUG: which must be 'insert' or 'delete"
        unless $which eq 'insert' || $which eq 'delete';
    my ($label, $label_sub);
    if (ref($args{label}) eq 'CODE') {
        $label = "FRAGMENT";
        $label_sub = $args{label};
    } else {
        $label = $args{label} // "FRAGMENT";
        $label_sub = \&_label;
    }

    my $text               = $args{text};
    defined($text) or return [400, "Please specify text"];
    my $id                 = $args{id};
    defined($id) or return [400, "Please specify id"];
    $id =~ /\A\w+\z/ or return [400, "Invalid id, please use ".
                                    "letters/numbers only"];
    my $good_pattern       = $args{good_pattern};
    my $replace_pattern    = $args{replace_pattern};
    my $top_style          = $args{top_style};
    my $comment_style      = $args{comment_style} // "shell";
    my $res                = $label_sub->(id=>$id, label=>$label,
                                          comment_style=>$comment_style);
    my $one_line_comment   = $res->{one_line_comment};
    my $begin_comment      = $res->{begin_comment};
    my $end_comment        = $res->{end_comment};
    my $one_line_pattern   = $res->{one_line_pattern};
    my $multi_line_pattern = $res->{multi_line_pattern};
    my $des_pl             = $args{payload}; # desired payload
    if ($which eq 'insert') {
        defined($des_pl) or return [400, "Please specify payload"];
    }

    my $is_multi           = $des_pl =~ /\R/;
    if ($is_multi) {
        # autoappend newline
        $des_pl =~ s/\R\z//; $des_pl .= "\n";
    } else {
        # autotrim one-line
        $des_pl =~ s/\s+\z//;
    }

    my $typ; # existing payload is 'oneline' or 'multi'
    my $or_pl; # original payload before we remove/replace
    my ($should_remove, $removed);
    my ($should_insert, $inserted);
    if ($text =~ /$one_line_pattern/ && ($typ = 'oneline') ||
            $text =~ /$multi_line_pattern/ && ($typ = 'multi')) {
        $or_pl = $1; # existing fragment's payload
        if ($which eq 'insert' && $or_pl ne $des_pl) {
            $log->tracef("fragment payload is >>>%s<<< ".
                             "but needs to be >>>%s<<<",
                         $or_pl, $des_pl);
            $should_insert++;
        } elsif ($which eq 'delete') {
            $log->tracef("fragment exists when it should be removed");
            $should_remove++;
        } else {
            return [304, "Nothing done, text already contains fragment"];
        }
    } else {
        if ($which eq 'delete') {
            return [304, "Nothing done, text already lacks fragment"];
        } else {
            if ($good_pattern && $text =~ /$good_pattern/) {
                $log->tracef("text contains good_pattern %s, so we don't need ".
                                 "to insert fragment", $good_pattern);
            } else {
                $log->tracef("fragment %s doesn't exist", $id);
                $should_insert++;
            }
        }
    }

    if ($should_remove) {
        if ($typ eq 'oneline') {
            $text =~ s!($one_line_pattern)!!;
        } else {
            $text =~ s!($multi_line_pattern)!!;
        }
        $removed++;
    }

    if ($should_insert) {
        my $fragment;
        if ($is_multi) {
            $fragment = join(
                "",
                $begin_comment, "\n",
                $des_pl,
                $end_comment,
            );
        } else {
            $fragment = $des_pl . $one_line_comment;
        }
        if ($replace_pattern && $text =~ /($replace_pattern)/) {
            $or_pl = $1;
            $text =~ s/$replace_pattern(\R?)/$fragment . $1/e;
        } elsif ($text =~ /$one_line_pattern/) {
            $text =~ s/$one_line_pattern(\R?)/$fragment . $1/;
        } elsif ($text =~ /$multi_line_pattern(\R?)/) {
            $text =~ s/$multi_line_pattern/$fragment . $1/;
        } elsif ($top_style) {
            $text = $fragment . "\n" . $text;
        } else {
            my $enl = $text =~ /\R\z/; # text ends with newline
            $text .= ($enl ? "" : "\n") . $fragment . ($enl ? "\n" : "");
        }
        $inserted++;
    }

    if ($inserted || $removed) {
        [200, "OK", {text=>$text, orig_payload=>$or_pl}];
    } else {
        return [304, "Nothing done"];
    }
}

$SPEC{insert_fragment} = {
    summary => 'Insert a fragment of text to another text',
    description => <<'_',

A fragment is a single line or a group of lines with an ID (and zero or more
attributes) attached to it. The ID and attributes are encoded in the comment.
Several types of comment styles are supported. Some examples of one-line
fragments:

    some text # FRAGMENT id=id1
    RSYNC_ENABLE=1 /* FRAGMENT id=enable */

An example of multi-line fragment (using cpp style comment instead of shell):

    // BEGIN FRAGMENT id=id2
    some
    lines
    of
    text
    // END FRAGMENT

Another example:

    ; BEGIN FRAGMENT id=default
    register_globals=On
    extension=mysql.so
    extension=gd.so
    memory_limit=256M
    post_max_size=64M
    upload_max_filesize=64M
    browscap=/c/share/php/browscap.ini
    allow_url_fopen=0
    ; END FRAGMENT id=default

Fragments are usually inserted into configuration files or code. They can be
removed later because they have an identifier associated with it.

_
    args => {
        text => {
            summary => 'The text to insert fragment into',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        id => {
            summary => 'Fragment ID',
            schema  => ['str*' => { match => qr/\A[\w-]+\z/ }],
            req     => 1,
            pos     => 1,
        },
        payload => {
            summary => 'Fragment content',
            schema  => 'str*',
            req     => 1,
            pos     => 2,
        },
        top_style => {
            summary => 'Whether to append fragment at beginning of file '.
                'instead of at the end',
            schema  => [bool => { default=>0 }],
            description => <<'_',

Default is false, which means to append at the end of file.

Note that this only has effect if `replace_pattern` is not defined or replace
pattern is not found in file. Otherwise, fragment will be inserted to replace
the pattern.

_
        },
        replace_pattern => {
            summary => 'Regex pattern which if found will be used for '.
                'placement of fragment',
            schema  => 'str',
            description => <<'_',

If fragment needs to be inserted into file, then if `replace_pattern` is defined
then it will be searched. If found, fragment will be placed to replace the
pattern. Otherwise, fragment will be inserted at the end (or beginning, see
`top_style`) of file.

_
        },
        good_pattern => {
            summary => 'Regex pattern which if found means fragment '.
                'need not be inserted',
            schema  => 'str',
        },
        comment_style => {
            summary => 'Comment style',
            schema  => ['str' => {
                default => 'shell',
                in      => [qw/c cpp html shell ini/],
            }],
            description => <<'_',

Fragment is inserted along with comment which contains metainformation such as
fragment ID and zero or more attributes.

Example of shell-style (shell) comment:

    ... # FRAGMENT id=...

    # BEGIN FRAGMENT id=...
    ...
    # END FRAGMENT

Example of C-style (c) comment:

    ... /* FRAGMENT id=... */

    /* BEGIN FRAGMENT id=... */
    ...
    /* END FRAGMENT id=... */

Example of C++-style (cpp) comment:

    ... // FRAGMENT id=...

    // BEGIN FRAGMENT id=...
    ...
    // END FRAGMENT id=...

Example of SGML-style (html) comment:

    ... <!-- FRAGMENT id=... -->

    <!-- BEGIN FRAGMENT id=... -->
    ...
    <!-- END FRAGMENT id=... -->

Example of INI-style comment:

    ... // FRAGMENT id=...

    ; BEGIN FRAGMENT id=...
    ...
    ; END FRAGMENT id=...

_
        },
        label => {
            schema  => ['any' => {
                of => ['str*', 'code*'],
                default => 'FRAGMENT',
            }],
            summary => 'Comment label',
            description => <<'_',

If label is string (e.g. `Foo`), then one-line fragment comment will be:

 # Foo id=...

and multi-line fragment comment:

 # BEGIN Foo id=...
 ...
 # END Foo id=...

If label is a code, it will be called with named arguments: `id`,
`comment_style`, `attrs` (a hash of attributes). It must return a hash with
these keys: `one_line_comment` (string, the comment for one-line fragment),
`begin_comment` (string, the beginning comment for multi-line fragment),
`end_comment` (string, the closing comment for multi-line fragment),
`one_line_pattern` (regex to match one-line fragment payload and extract it in
$1), and `multi_line_pattern` (regex to match multi-line fragment content and
extract it in $1).

_
        },
    },
    result => {
        summary => 'A hash of result',
        schema  => 'hash*',
        description => <<'_',

Will return status 200 if operation is successful and text is changed. The
result is a hash with the following keys: `text` will contain the new text,
`orig_payload` will contain the original payload before being removed/replaced.

Will return status 304 if nothing is changed (for example, if fragment with the
same payload needs to be inserted and has been; or when fragment needs to be
deleted and already does not exist in the text).

_
    },
};
sub insert_fragment {
    _insert_or_delete_fragment('insert', @_);
}

$SPEC{delete_fragment} = clone($SPEC{insert_fragment});
$SPEC{delete_fragment}{summary} = 'Delete fragment from text';
$SPEC{delete_fragment}{description} = <<'_';

See `insert_fragment` for more information on fragment.

_
delete $SPEC{delete_fragment}{args}{payload};
sub delete_fragment {
    _insert_or_delete_fragment('delete', @_);
}

1;
# ABSTRACT: Insert/remove fragment in text

=head1 SYNOPSIS

 use Text::Fragment qw(insert_fragment remove_fragment);

 my $text = <<_;
 foo = "some value"
 baz = 0
 _

To insert a fragment:

 my $res = insert_fragment(text=>$text, id=>'bar', payload=>'bar = 2');

C<< $res->[2]{text} >> will now contain:

 foo = "some value"
 baz = 0
 bar = 2 # FRAGMENT id=bar

To replace a fragment:

 $res = insert_fragment(text=>$res->[2], id='bar', payload=>'bar = 3');

C<< $res->[2]{text} >> will now contain:

 foo = "some value"
 baz = 0
 bar = 3 # FRAGMENT id=bar

and C<< $res->[2]{orig_payload} >> will contain the payload before being
replaced:

 bar = 2

To delete a fragment:

 $res = delete_fragment(text=>$res->[2], id=>'bar');

=cut
