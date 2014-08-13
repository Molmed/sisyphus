use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Sisyphus',
  VERSION_FROM => 'VERSION',
  test => {TESTS => 't/*.t'}
);

