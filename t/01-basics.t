#!perl

use 5.010;
use strict;
use warnings;
use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use Text::Fragment qw(insert_fragment delete_fragment);
use Test::More 0.98;

test_insert_fragment(
    name          => "insert one-line/shell",
    args          => {text=>"1\n2\n3\n", id=>"id1", payload=>"x"},
    status        => 200,
    text          => "1\n2\n3\nx # FRAGMENT id=id1\n",
    orig_payload  => undef,
);
test_insert_fragment(
    name          => "insert one-line/shell, no ending newline",
    args          => {text=>"1\n2\n3", id=>"id1", payload=>"x"},
    status        => 200,
    text          => "1\n2\n3\nx # FRAGMENT id=id1",
    orig_payload  => undef,
);
test_insert_fragment(
    name          => "insert one-line/shell, noop",
    args          => {text=>"1\n2\n3\nx # FRAGMENT id=id1",
                      id=>"id1", payload=>"x"},
    status        => 304,
);

# XXX test remove orig no ending newline -> restored with no ending nl

test_setup_snippet_with_id(
    name          => "insert multiline/shell, autoappend newline",
    prepare       => sub { write_file($f, "1\n2\n3") },
    args          => {file=>$f, id=>"i", content=>"x\ny\n"},
    check_unsetup => {content => qr/^1\n2\n3\n?/},
    check_setup   => {content => "1\n2\n3\n".
                          "# BEGIN SNIPPET id=i\nx\ny\n# END SNIPPET id=i\n"},
);
test_setup_snippet_with_id(
    name          => "insert one-line/c, label (string)",
    prepare       => sub { write_file($f, "1\n2\n3\n") },
    args          => {file=>$f, id=>"i", content=>" x", label=>"Label",
                      comment_style=>'c'},
    check_unsetup => {content => "1\n2\n3\n"},
    check_setup   => {content => "1\n2\n3\n".
                          " x /* Label id=i */\n"},
);
test_setup_snippet_with_id(
    name          => "insert one-line/c, label (string)",
    prepare       => sub { write_file($f, "1\n2\n3\n") },
    args          => {file=>$f, id=>"i", content=>" x\n y\n", label=>"Lbl",
                      comment_style=>'c'},
    check_unsetup => {content => "1\n2\n3\n"},
    check_setup   => {content => "1\n2\n3\n".
                          "/* BEGIN Lbl id=i */\n x\n y\n/* END Lbl id=i */\n"},
);
test_setup_snippet_with_id(
    name          => "insert one-line/html, autotrim",
    prepare       => sub { write_file($f, "") },
    args          => {file=>$f, id=>"i", content=>"x", comment_style=>'html'},
    check_unsetup => {content => ""},
    check_setup   => {content => "x <!-- SNIPPET id=i -->\n"},
);
test_setup_snippet_with_id(
    name          => "insert multiline/html",
    prepare       => sub { write_file($f, "") },
    args          => {file=>$f, id=>"i", content=>"x  \n y",
                      comment_style=>'html'},
    check_unsetup => {content => ""},
    check_setup   => {content => "<!-- BEGIN SNIPPET id=i -->\nx  \n y\n".
                          "<!-- END SNIPPET id=i -->\n"},
);
test_setup_snippet_with_id(
    name          => "insert one-line/ini, top_style",
    prepare       => sub { write_file($f, "1\n2") },
    args          => {file=>$f, id=>"i", content=>"x", comment_style=>'ini',
                      top_style=>1},
    check_unsetup => {content => "1\n2"},
    check_setup   => {content => "x ; SNIPPET id=i\n1\n2"},
);
test_setup_snippet_with_id(
    name          => "insert multiline/ini, top_style",
    prepare       => sub { write_file($f, "1\n2") },
    args          => {file=>$f, id=>"i", content=>"x\ny", comment_style=>'ini',
                      top_style=>1},
    check_unsetup => {content => "1\n2"},
    check_setup   => {content => "; BEGIN SNIPPET id=i\nx\ny\n".
                          "; END SNIPPET id=i\n1\n2"},
);
test_setup_snippet_with_id(
    name          => "insert multiline, top_style",
    prepare       => sub { write_file(
        $f, "1 # SNIPPET attr1=a id=i2 attr2=b\n") },
    args          => {file=>$f, id=>"i2", content=>"x", should_exist=>0,
                      top_style=>1},
    check_unsetup => {content =>
                          qr/^1 # SNIPPET (attr1=a )?id=i2( attr2=b)?\n/},
    # XXX attr is not preserved yet
    check_setup   => {content => ""},
);
test_setup_snippet_with_id(
    name          => "file doesn't exist, should_exist=>1",
    prepare       => sub { unlink $f },
    args          => {file=>$f, id=>"i", content=>"x", should_exist=>1},
    check_unsetup => {exists => 0},
    do_error      => 500,
);
test_setup_snippet_with_id(
    name          => "file doesn't exist, should_exist=>0",
    prepare       => sub { unlink $f },
    args          => {file=>$f, id=>"i", content=>"x", should_exist=>0},
    check_unsetup => {exists => 0},
    check_setup   => {exists => 0},
);
test_setup_snippet_with_id(
    name          => "insert, replace_pattern",
    prepare       => sub { write_file($f, "1\n2\n3\n") },
    args          => {file=>$f, id=>"i", content=>"x",
                      replace_pattern=>qr/^2\n/m},
    check_unsetup => {content => "1\n2\n3\n"},
    check_setup   => {content => "1\nx # SNIPPET id=i\n3\n"},
);
test_setup_snippet_with_id(
    name          => "insert, replace_pattern not found",
    prepare       => sub { write_file($f, "1\n2\n3\n") },
    args          => {file=>$f, id=>"i", content=>"x",
                      replace_pattern=>qr/^4\n/m},
    check_unsetup => {content => "1\n2\n3\n"},
    check_setup   => {content => "1\n2\n3\nx # SNIPPET id=i\n"},
);
test_setup_snippet_with_id(
    name          => "insert, good_pattern",
    prepare       => sub { write_file($f, "1\n2\n3\n") },
    args          => {file=>$f, id=>"i", content=>"x",
                      good_pattern=>qr/^2\n/m},
    check_unsetup => {content => "1\n2\n3\n"},
    check_setup   => {content => "1\n2\n3\n"},
);
test_setup_snippet_with_id(
    name          => "insert, good_pattern not found",
    prepare       => sub { write_file($f, "1\n2\n3\n") },
    args          => {file=>$f, id=>"i", content=>"x",
                      good_pattern=>qr/^4\n/m},
    check_unsetup => {content => "1\n2\n3\n"},
    check_setup   => {content => "1\n2\n3\nx # SNIPPET id=i\n"},
);
test_setup_snippet_with_id(
    name          => "update one-line",
    prepare       => sub { write_file(
        $f, "1\n2 # SNIPPET id=i\n3\n") },
    args          => {file=>$f, id=>"i", content=>"3"},
    check_unsetup => {content => "1\n2 # SNIPPET id=i\n3\n"},
    check_setup   => {content => "1\n3 # SNIPPET id=i\n3\n"},
);
test_setup_snippet_with_id(
    name          => "update multiline",
    prepare       => sub { write_file(
        $f, "1\n# BEGIN SNIPPET id=i\n2\n3\n".
            "# END SNIPPET id=i\n3\n") },
    args          => {file=>$f, id=>"i", content=>"3\n4\n"},
    check_unsetup => {content =>
                          "1\n# BEGIN SNIPPET id=i\n2\n3\n".
                              "# END SNIPPET id=i\n3\n"},
    check_setup   => {content =>
                          "1\n# BEGIN SNIPPET id=i\n3\n4\n".
                              "# END SNIPPET id=i\n3\n"},
);

DONE_TESTING:
done_testing;

sub test_insert_fragment {
}

sub test_delete_fragment {
}
