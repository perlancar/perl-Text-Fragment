#!perl

use 5.010;
use strict;
use warnings;
use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use Text::Fragment qw(list_fragments);
use Test::More 0.98;

subtest "empty" => sub {
    my $text = <<'_';
1
2
3
4 // FRAGMENT id=id1 cause=different-label
5 # DIFFERENT_LABEL id=id2
_

    is_deeply(
        list_fragments(text=>$text),
        [200, "OK", [
        ]]);
};

subtest "list" => sub {
    my $text = <<'_';
1
2
3
4 # FRAGMENT id=id1 a=1 b=2
# BEGIN FRAGMENT id=id2
a
b
# END FRAGMENT
 5  #FRAGMENT  id=id3
# BEGIN FRAGMENT id=id4
c
# END FRAGMENT
# END FRAGMENT id=id4
_

    is_deeply(
        list_fragments(text=>$text),
        [200, "OK", [
            {
                raw     => "4 # FRAGMENT id=id1 a=1 b=2\n",
                id      => "id1",
                attrs   => {id=>"id1", a=>1, b=>2},
                payload => "4",
            },
            {
                raw     => "# BEGIN FRAGMENT id=id2\na\nb\n# END FRAGMENT\n",
                id      => "id2",
                attrs   => {id=>"id2"},
                payload => "a\nb\n",
            },
            {
                raw     => " 5  #FRAGMENT  id=id3\n",
                id      => "id3",
                attrs   => {id=>"id3"},
                payload => " 5",
            },
            {
                raw     => "# BEGIN FRAGMENT id=id4\nc\n# END FRAGMENT\n".
                    "# END FRAGMENT id=id4\n",
                id      => "id4",
                attrs   => {id=>"id4"},
                payload => "c\n# END FRAGMENT\n",
            },
        ]]);
};

subtest "multi-word label, c-style comment" => sub {
    my $text = <<'_';
1
2
3 /* FRAGMENT id=id0 */
4 /* SPANEL SECTION id=id-1 */
5
_

    is_deeply(
        list_fragments(text=>$text,
                       comment_style=>"c", label=>"SPANEL SECTION"),
        [200, "OK", [
            {
                raw     => "4 /* SPANEL SECTION id=id-1 */\n",
                id      => "id-1",
                attrs   => {id=>"id-1"},
                payload => "4",
            },
        ]]);
};

DONE_TESTING:
done_testing;
