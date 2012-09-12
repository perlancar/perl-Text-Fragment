#!perl

use 5.010;
use strict;
use warnings;
use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use Text::Fragment qw(insert_fragment);
use Test::More 0.98;

test_insert_fragment(
    name          => "insert one-line/shell, noop",
    args          => {text=>"1\n2\n3\nx # FRAGMENT id=id1",
                      id=>"id1", payload=>"x"},
    status        => 304,
);
test_insert_fragment(
    name          => "insert one-line/shell",
    args          => {text=>"1\n2\n3\n", id=>"id1", payload=>"x"},
    text          => "1\n2\n3\nx # FRAGMENT id=id1\n",
);
test_insert_fragment(
    name          => "insert one-line/shell, set attrs",
    args          => {text=>"1\n2\n3\n", id=>"id1", payload=>"x",
                      attrs=>{a=>1, b=>2}},
    text          => "1\n2\n3\nx # FRAGMENT id=id1 a=1 b=2\n",
);
test_insert_fragment(
    name          => "insert one-line/shell, no ending newline",
    args          => {text=>"1\n2\n3", id=>"id1", payload=>"x"},
    text          => "1\n2\n3\nx # FRAGMENT id=id1",
);
test_insert_fragment(
    name          => "insert one-line/c, top style",
    args          => {text=>"1\n2\n3", id=>"id1", payload=>"x",
                      comment_style=>'c', top_style=>1},
    text          => "x /* FRAGMENT id=id1 */\n1\n2\n3",
);
test_insert_fragment(
    name          => "insert one-line/cpp, label",
    args          => {text=>"1\n2\n3\n", id=>"id1", payload=>"x",
                      comment_style=>"cpp", label=>"X"},
    text          => "1\n2\n3\nx // X id=id1\n",
);

test_insert_fragment(
    name          => "good_pattern",
    args          => {text=>"1\n2\n3\n", id=>"id1", payload=>"x",
                      good_pattern=>qr/^2/m},
    status        => 304,
);

test_insert_fragment(
    name          => "replace single-line/html, replace_pattern",
    args          => {text=>"1\n2\n3\n", id=>"id1", payload=>"x",
                      comment_style=>"html", replace_pattern=>qr/^2\R/m},
    text          => "1\nx <!-- FRAGMENT id=id1 -->\n3\n",
);
test_insert_fragment(
    name          => "replace multiline/ini",
    args          => {text=><<'_',id=>"id1",payload=>"x",comment_style=>"ini"},
1
; BEGIN FRAGMENT id=id1
2
; END FRAGMENT
_
    text          => "1\n; BEGIN FRAGMENT id=id1\nx\n; END FRAGMENT id=id1\n",
    orig_fragment => "; BEGIN FRAGMENT id=id1\n2\n; END FRAGMENT\n",
    orig_payload  => "2\n",
);

# XXX test: replace doesn't replace existing attrs, use set_fragment_attrs() for
# that

DONE_TESTING:
done_testing;

sub test_insert_fragment {
    my %targs = @_;

    subtest $targs{name} => sub {
        my $res = insert_fragment(%{ $targs{args} });
        my $status = $targs{status} // 200;
        is($res->[0], $status, 'status');
        return if $status != 200;
        for (qw/text orig_payload orig_fragment/) {
            if (defined $targs{$_}) {
                is($res->[2]{$_}, $targs{$_}, $_);
            }
        }
    };
}
