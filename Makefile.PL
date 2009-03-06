use inc::Module::Install;

name     'Quiz-Flashcards';
all_from 'lib/Quiz/Flashcards.pm';
author   'Christian Walde <mithaldu@yahoo.de>';
license  'perl';

build_requires 'Test::More';
build_requires 'Wx';
build_requires 'DBI';
build_requires 'Module::Find';
build_requires 'Time::HiRes';
build_requires 'Module::Install::Share';
build_requires 'File::ShareDir';

auto_install;

install_share;

WriteAll;

