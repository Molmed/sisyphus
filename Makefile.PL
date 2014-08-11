use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Sisyphus',
  VERSION_FROM => 'version.pl',
  test => {TESTS => 't/*.t'}
);

