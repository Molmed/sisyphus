use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Sisyphus',
  VERSION_FROM => 'lib/Molmed/Sisyphus/Version.pm',
  test => {TESTS => 't/*.t'}
);

