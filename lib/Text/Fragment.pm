package Text::Fragment;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Data::Clone;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                       list_fragments
                       get_fragment
                       set_fragment_attrs
                       insert_fragment
                       delete_fragment
               );

our $re_id = qr/\A[A-Za-z0-9_.,:-]+\z/;

our %SPEC;

sub _label {
    my %args  = @_;
    my $id            = $args{id} // "";
    my $label         = $args{label}; # str
    my $comment_style = $args{comment_style};
    my $attrs         = $args{attrs};

    my $a_re;  # regex to match attributes
    my $ai_re; # also match attributes, but attribute id must be present
    if (length $id) {
        $ai_re = qr/(?:\w+=\S*[ \t]+)*id=(?<id>\Q$id\E)(?:[ \t]+\w+=\S+)*/;
    } else {
        $ai_re = qr/(?:\w+=\S*[ \t]+)*id=(?<id>\S*)(?:[ \t]+\w+=\S+)*/;
    }
    $a_re  = qr/(?:\w+=\S*)?(?:[ \t]+\w+=\S*)*/;

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
    }
    # regex to detect fragment
    my $ore = qr!^(?<payload>.*?)[ \t]*\Q$ts\E[ \t]*
                 \Q$label\E[ \t]+
                 (?<attrs>$ai_re)[ \t]*
                 \Q$te\E[ \t]*(?<enl>\R|\z)!mx;

    my $mre = qr!^\Q$ts\E[ \t]*
                 BEGIN[ \t]+\Q$label\E[ \t]+
                 (?<attrs>$ai_re)[ \t]*
                 \Q$te\E[ \t]*(?<is_multi>\R)
                 (?:
                     (?<payload>.*)
                     ^\Q$ts\E[ \t]*END[ \t]+\Q$label\E[ \t]+
                       (?:\w+=\S*[ \t]+)*id=\g{id}(?:[ \t]+\w+=\S+)*
                       [ \t]*\Q$te\E |
                     (?<payload>.*?) # without any ID at the ending comment
                     ^\Q$ts\E[ \t]*END[ \t]+\Q$label\E(?:[ \t]+$a_re)?[ \t]*
                     \Q$te\E
                 )
                 [ \t]*(?<enl>\R|\z)!msx;

    my $parse_attrs = sub {
        my $s = shift // "";
        my %a;
        for my $a (split /[ \t]+/, $s) {
            my ($n, $v) = split /=/, $a, 2;
            $a{$n} = $v;
        }
        \%a;
    };

    return {
        one_line_pattern   => $ore,
        multi_line_pattern => $mre,
        parse_attrs        => $parse_attrs,
        format_fragment    => sub {
            my %f = @_;

            # formatted attrs as string
            my $as = "";
            if (ref($f{attrs})) {
                for (sort keys %{ $f{attrs} }) {
                    $as .= " " . "$_=$f{attrs}{$_}";
                }
            } else {
                my $a = $parse_attrs->($f{attrs});
                $as = join(" ", map {"$_=$a->{$_}"} grep {$_ ne 'id'}
                    sort keys %$a);
            }

            my $pl = $f{payload};

            # to keep things simple here, regardless of whether the replaced
            # pattern contains ending newline (enl), we still format with ending
            # newline. then we'll just need to strip ending newline if it's not
            # needed.

            if ($f{is_multi} || $pl =~ /\R/) {
                $pl .= "\n" unless $pl =~ /\R\z/;
                "$ts BEGIN $label id=$id$as" . ($te ? " $te":"") . "\n" .
                $pl .
                "$ts END $label id=$id" . ($te ? " $te":"") . "\n";
            } else {
                "$pl $ts $label id=$id$as" . ($te ? " $te":"") . "\n";
            }
        },
    };
}

sub _doit {
    my ($which, %args) = @_;

    die "BUG: invalid which"
        unless $which =~ /\A(?:list|get|insert|delete|set_attrs)\z/;
    my ($label_str, $label_sub);
    if (ref($args{label}) eq 'CODE') {
        $label_str = "FRAGMENT";
        $label_sub = $args{label};
    } else {
        $label_str = $args{label} || "FRAGMENT";
        $label_sub = \&_label;
    }

    my $text               = $args{text};
    defined($text) or return [400, "Please specify text"];
    my $id                 = $args{id};
    if ($which =~ /\A(?:get|insert|set_attrs|delete)\z/) {
        defined($id) or return [400, "Please specify id"];
    }
    if (defined $id) {
        $id =~ $re_id or return [400, "Invalid syntax for id, please use ".
                                     "letters/numbers/dots/dashes only"];
    }
    my $attrs              = $args{attrs} // {};
    for (keys %$attrs) {
        /\A\w+\z/ or return [400, "Invalid attribute name '$_', please use ".
                                 "letters/numbers only"];
        if (!defined($attrs->{$_})) {
            if ($which eq 'set_attrs') {
                next;
            } else {
                return [400, "Undefined value for attribute name '$_'"];
            }
        }
        $attrs->{$_} =~ /\s/s and return
            [400,"Invalid value in attribute '$_', no whitespaces please"];
    }

    my $good_pattern       = $args{good_pattern};
    my $replace_pattern    = $args{replace_pattern};
    my $top_style          = $args{top_style};
    my $comment_style      = $args{comment_style} // "shell";
    $comment_style =~ /\A(cpp|c|shell|html|ini)\z/ or return [
        400, "Invalid comment_style, please use cpp/c/shell/html/ini"];
    my $res                = $label_sub->(id=>$id, label=>$label_str,
                                          comment_style=>$comment_style);
    my $one_line_pattern   = $res->{one_line_pattern};
    my $multi_line_pattern = $res->{multi_line_pattern};
    my $parse_attrs        = $res->{parse_attrs};
    my $format_fragment    = $res->{format_fragment};
    my $payload            = $args{payload};
    if ($which eq 'insert') {
        defined($payload) or return [400, "Please specify payload"];
    }

    if ($which eq 'list') {

        my @ff;
        while ($text =~ /($one_line_pattern|$multi_line_pattern)/xg) {
            push @ff, {
                raw     => $1,
                id      => $+{id},
                payload => $+{payload},
                attrs   => $parse_attrs->($+{attrs}),
            };
        }
        return [200, "OK", \@ff];

    } elsif ($which eq 'get') {

        say $one_line_pattern;
        if ($text =~ /($one_line_pattern|$multi_line_pattern)/x) {
            return [200, "OK", {
                raw     => $1,
                id      => $+{id},
                payload => $+{payload},
                attrs   => $parse_attrs->($+{attrs}),
            }];
        } else {
            return [404, "Fragment with that ID not found"];
        }

    } elsif ($which eq 'set_attrs') {

        my $orig_attrs;
        my $sub = sub {
            my %f = @_;
            $orig_attrs = $parse_attrs->($f{attrs});
            my %a = %$orig_attrs; delete $a{id};
            for my $k (keys %$attrs) {
                my $v = $attrs->{$k};
                if (defined $v) {
                    $a{$k} = $v;
                } else {
                    delete $a{$k};
                }
            }
            $f{attrs} = \%a;
            $format_fragment->(%f);
        };
        if ($text =~ s{$one_line_pattern | $multi_line_pattern}
                      {$sub->(%+)}egx) {
            return [200, "OK", {text=>$text, orig_attrs=>$orig_attrs}];
        } else {
            return [404, "Fragment with that ID not found"];
        }

    } elsif ($which eq 'delete') {

        my %f;
        my $sub = sub {
            %f = @_;
            $f{enl} ? $f{bnl} : "";
        };
        if ($text =~ s{(?<bnl>\R?)
                       (?<fragment>$one_line_pattern | $multi_line_pattern)}
                      {$sub->(%+)}egx) {
            use DD; dd \%f;
            return [200, "OK", {text=>$text,
                                orig_fragment=>$f{fragment},
                                orig_payload=>$f{payload}}];
        } else {
            return [304, "Fragment with that ID already does not exist"];
        }

    } else { # insert

        my $replaced;
        my %f;
        my $sub = sub {
            %f = @_;
            return $f{fragment} if $payload eq $f{payload};
            $replaced++;
            $f{orig_fragment} = $f{fragment};
            $f{orig_payload} = $f{payload};
            $f{payload} = $payload;
            $format_fragment->(%f);
        };
        if ($good_pattern && $text =~ /$good_pattern/) {
            return [304, "Text contains good pattern"];
        }

        if ($text =~ s{(?<fragment>(?:$one_line_pattern | $multi_line_pattern))}
                      {$sub->(%+)}ex) {
            if ($replaced) {
                return [200, "Payload replaced", {
                    text=>$text, orig_fragment=>$f{orig_fragment},
                    orig_payload=>$f{orig_payload}}];
            } else {
                return [304, "Fragment with that ID already exist with ".
                            "same content"];
            }
        }

        my $fragment = $format_fragment->(payload=>$payload, attrs=>$attrs);
        if ($replace_pattern && $text =~ /($replace_pattern)/) {
            my $orig_fragment = $1;
            $text =~ s/$replace_pattern/$fragment/;
            return [200, "Replace pattern replaced", {
                text=>$text, orig_fragment=>$orig_fragment}];
        }

        if ($top_style) {
            $text = $fragment . $text;
        } else {
            my $enl = $text =~ /\R\z/; # text ends with newline
            $fragment =~ s/\R\z// unless $enl;
            $text .= ($enl ? "" : "\n") . $fragment;
        }
        return [200, "Fragment inserted at the ".
                    ($top_style ? "top" : "bottom"), {text=>$text}];
    }

}

$SPEC{':package'} = {
    v => 1.1,
    summary     => 'Manipulate fragments in text',
    description => <<'_',

A fragment is a single line or a group of lines (called payload) with a metadata
encoded in the comment that is put adjacent to it (for a single line fragment)
or enclosing it (for a multiline fragment). Fragments are usually used in
configuration files or code. Here is the structure of a single-line fragment:

    <payload> # <label> <attrs>

Here is the structure of a multi-line fragment:

    # BEGIN <label> <attrs>
    <payload>
    # END <label> [<attrs>]

Label is by default `FRAGMENT` but can be other string. Attributes are a
sequence of `name=val` separated by whitespace, where name must be alphanums
only and val is zero or more non-whitespace characters. There must at least be
an attribute with name `id`, it is used to identify fragment and allow the
fragment to be easily replaced/modified/deleted from text. Attributes are
optional in the ending comment.

Comment character used is by default `#` (`shell`-style comment), but other
comment styles are supported (see below).

Examples of single-line fragments (the second example uses `c`-style comment and
the third uses `cpp`-style comment):

    RSYNC_ENABLE=1 # FRAGMENT id=enable
    some text /* FRAGMENT id=id2 */
    some text // FRAGMENT id=id3 foo=1 bar=2

An example of multi-line fragment (using `html`-style comment instead of
`shell`):

    <!-- BEGIN FRAGMENT id=id4 -->
    some
    lines
    of
    text
    <!-- END FRAGMENT id=id4 -->

Another example (using `ini`-style comment):

    ; BEGIN FRAGMENT id=default-settings
    register_globals=On
    extension=mysql.so
    extension=gd.so
    memory_limit=256M
    post_max_size=64M
    upload_max_filesize=64M
    browscap=/c/share/php/browscap.ini
    allow_url_fopen=0
    ; END FRAGMENT

_
};

my $arg_comment_style = {
    summary => 'Comment style',
    schema  => ['str' => {
        default => 'shell',
        in      => [qw/c cpp html shell ini/],
    }],
};
my $arg_label = {
    schema  => [str => {default=>'FRAGMENT'}],
    summary => 'Comment label',
};

my $arg_id = {
    summary => 'Fragment ID',
    schema  => ['str*' => { match => qr/\A[\w-]+\z/ }],
    req     => 1,
};

my $arg_payload = {
    summary => 'Fragment content',
    schema  => 'str*',
    req     => 1,
};

$SPEC{list_fragments} = {
    v => 1.1,
    summary => 'List fragments in text',
    args => {
        text          => {
            summary => 'The text which contain fragments',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        comment_style => $arg_comment_style,
        label         => $arg_label,
    },
    result => {
        summary => 'List of fragments',
        schema  => 'array*',
        description => <<'_',

Will return status 200 if operation is successful. Result will be an array of
fragments, where each fragment is a hash containing these keys: `raw` (string),
`payload` (string), `attrs` (hash), `id` (string, can also be found in
attributes).

_
    },
};
sub list_fragments {
    _doit('list', @_);
}

$SPEC{get_fragment} = {
    v => 1.1,
    summary => 'Get fragment with a certain ID in text',
    description => <<'_',

If there are multiple occurences of the fragment with the same ID ,

_
    args => {
        text          => {
            summary => 'The text which contain fragments',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        comment_style => $arg_comment_style,
        label         => $arg_label,
        id            => $arg_id,
    },
    result => {
        summary => 'Fragment',
        schema  => 'array*',
        description => <<'_',

Will return status 200 if fragment is found. Result will be a hash with the
following keys: `raw` (string), `payload` (string), `attrs` (hash), `id`
(string, can also be found in attributes).

Return 404 if fragment is not found.

_
    },
};
sub get_fragment {
    _doit('get', @_);
}

$SPEC{set_fragment_attrs} = {
    v => 1.1,
    summary => 'Set/unset attributes of a fragment',
    description => <<'_',

If there are multiple occurences of the fragment with the same ID ,

_
    args => {
        text          => {
            summary => 'The text which contain fragments',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        comment_style => $arg_comment_style,
        label         => $arg_label,
        id            => $arg_id,
        attrs         => {
            schema => 'hash*',
            description => <<'_',

To delete an attribute in the fragment, you can set the value to undef.

_
            req    => 1,
        },
    },
    result => {
        summary => 'New text and other data',
        schema  => 'array*',
        description => <<'_',

Will return status 200 if fragment is found. Result will be a hash containing
these keys: `text` (string, the modified text), `orig_attrs` (hash, the old
attributes before being modified).

Return 404 if fragment is not found.

_
    },
};
sub set_fragment_attrs {
    _doit('set_attrs', @_);
}

$SPEC{insert_fragment} = {
    v => 1.1,
    summary => 'Insert or replace a fragment in text',
    description => <<'_',

Newline insertion behaviour: if fragment is inserted at the bottom and text does
not end with newline (which is considered bad style), the inserted fragment will
also not end with newline.

_
    args => {
        text      => {
            summary => 'The text to insert fragment into',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        id        => $arg_id,
        payload   => $arg_payload,
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
        comment_style => $arg_comment_style,
        label         => $arg_label,
        attrs         => {
            schema => [hash => {default=>{}}],
        },
    },
    result => {
        summary => 'A hash of result',
        schema  => 'hash*',
        description => <<'_',

Will return status 200 if operation is successful and text is changed. The
result is a hash with the following keys: `text` will contain the new text,
`orig_payload` will contain the original payload before being removed/replaced,
`orig_fragment` will contain the original fragment (or the text that matches
`replace_pattern`).


Will return status 304 if nothing is changed (i.e. if fragment with the
same payload that needs to be inserted already exists in the text).

_
    },
};
sub insert_fragment {
    _doit('insert', @_);
}

$SPEC{delete_fragment} = {
    v => 1.1,
    summary => 'Delete fragment in text',
    description => <<'_',

If there are multiple occurences of fragment (which is considered an abnormal
condition), all occurences will be deleted.

Newline deletion behaviour: if fragment at the bottom of text does not end with
newline (which is considered bad style), the text after the fragment is deleted
will also not end with newline.

_
    args => {
        text => {
            summary => 'The text to delete fragment from',
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
        comment_style => $arg_comment_style,
        label => {
            schema  => ['any' => {
                of => ['str*', 'code*'],
                default => 'FRAGMENT',
            }],
            summary => 'Comment label',
        },
    },
    result => {
        summary => 'A hash of result',
        schema  => 'hash*',
        description => <<'_',

Will return status 200 if operation is successful and text is deleted. The
result is a hash with the following keys: `text` will contain the new text,
`orig_payload` will contain the original fragment payload before being deleted,
`orig_fragment` will contain the original fragment. If there are multiple
occurences (which is considered an abnormal condition), only the last deleted
fragment will be returned in `orig_payload` and `orig_fragment`.

Will return status 304 if nothing is changed (i.e. when the fragment that needs
to be deleted already does not exist in the text).

_
    },
};
sub delete_fragment {
    _doit('delete', @_);
}

1;
# ABSTRACT: Manipulate fragments in text

=head1 SYNOPSIS

 use Text::Fragment qw(list_fragments
                       get_fragment
                       set_fragment_attrs
                       insert_fragment
                       delete_fragment);

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

To list fragments:

 $res = list_fragment(text=>$text);

To get a fragment:

 $res = get_fragment(text=>$text, id=>'bar');

To set fragment attributes:

 $res = se_fragment_attrs(text=>$text, id=>'bar', attrs=>{name=>'val', ...});

=cut
