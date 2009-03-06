package Quiz::Flashcards;
use warnings;
use strict;

use base 'Exporter';

our @EXPORT = (qw( run_flashcard_app ));

use Carp;
use utf8;
use English qw(-no_match_vars);

use Wx;

run_flashcard_app() unless caller();

=head1 NAME

Quiz::Flashcards - Cross-platform modular flashcard GUI application

=cut

our $VERSION = '0.02';   # define version

=head1 DESCRIPTION

Created out of the need to aid in language studies while being able to quickly adapt the program for a higher learning efficiency than most showy flashcard applications allow. This application focuses not on teaching new material, but on training and reinforcing already learned material.

It uses wxPerl for the GUI, which should make it work on most major desktop platforms. Additionally it stores data about the user's certainty and speed in answers in a SQLite database located in the user's data directory.

Flashcard sets as well as additional data like sound files to go along with the sets will be available as seperate modules in the Quiz::Flashcards::Sets:: and Quiz::Flashcards::Audiobanks:: namespaces.

=head1 SYNOPSIS

    use Edu::Flashcards;
    run_flashcard_app();

=head1 FUNCTIONS

=head2 run_flashcard_app

Starts the application itself.

=cut

sub run_flashcard_app {
    my $app = Quiz::Flashcards::App->new;
    $app->MainLoop;
}

=head1 AUTHOR

Christian Walde, C<< <mithaldu at yahoo.de> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-Quiz-flashcards at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Quiz-Flashcards>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find the source code repository with public read access on Google Code.

=over 4

=item

L<http://edu-flashcards.googlecode.com>

=back


You can find documentation for this module with the perldoc command.

    perldoc Quiz::Flashcards


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Quiz-Flashcards>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Quiz-Flashcards>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Quiz-Flashcards>

=item * Search CPAN

L<http://search.cpan.org/dist/Quiz-Flashcards/>

=back


=head1 RELATED

L<Wx>, L<DBD::SQLite>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Christian Walde, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

################################################################################

package Quiz::Flashcards::App;

use strict;
use base 'Wx::App';

sub OnInit {

    my $frame = Quiz::Flashcards::App::MainFrame->new;
    $frame->Show(1);
}

################################################################################

package Quiz::Flashcards::App::MainFrame;

use strict;
use base 'Wx::Frame';
use utf8;
use Wx::Event qw(:everything);
use Wx qw(:everything);
use DBI;
use Carp;
use Module::Find;
use Time::HiRes qw( time );
use Wx::Perl::ListCtrl;
use File::ShareDir ':ALL';
use File::Spec::Functions;

use lib '.';
use lib '..';

sub new {

    # set up self
    my $ref  = shift;
    my $self = $ref->SUPER::new(
        undef,                # parent window
        -1,                   # ID -1 means any
        'Quiz::Flashcards',    # title
        [ -1, -1 ],           # default position
        [ -1, -1 ],           # size
    );

    # get config
    $self->{dbh} = setup_database();
    $self->{c} = $self->{dbh}->selectall_hashref( "SELECT * FROM settings;", 'name' );

    for my $key ( keys %{ $self->{c} } ) {
        $self->{c}->{$key} = $self->{c}->{$key}->{value};
    }

    # look for card sets
    my @found = findallmod Quiz::Flashcards::Sets;
    for my $module (@found) {
        $module =~ s/Quiz::Flashcards::Sets:://;
        $module =~ s/::/ -> /;
    }

    #setup_menus( $self );

    # set up panel to work in
    my $panel = Wx::Panel->new( $self, -1, );

    # create ui elements
    $self->{start_next_button} = Wx::Button->new( $panel, -1, 'Start', [ -1, -1 ], [ -1, -1 ], wxBU_EXACTFIT, );
    $self->{set_status_button} =
      Wx::Button->new( $panel, -1, 'i', [ -1, -1 ], [ -1, -1 ], wxBU_EXACTFIT | wxBORDER_NONE, );

    $self->{answer_success}       = Wx::StaticText->new( $panel, -1, "",    [ -1, -1 ], [ -1, -1 ], wxALIGN_CENTRE, );
    $self->{answer_time}          = Wx::StaticText->new( $panel, -1, "",    [ -1, -1 ], [ -1, -1 ], wxALIGN_CENTRE, );
    $self->{question}             = Wx::StaticText->new( $panel, -1, "",    [ -1, -1 ], [ -1, -1 ], wxALIGN_CENTRE, );
    $self->{correct_answer}       = Wx::StaticText->new( $panel, -1, "",    [ -1, -1 ], [ -1, -1 ], wxALIGN_CENTRE, );
    $self->{question_description} = Wx::StaticText->new( $panel, -1, "",    [ -1, -1 ], [ -1, -1 ], wxALIGN_CENTRE, );
    $self->{set_status_summary}   = Wx::StaticText->new( $panel, -1, "",    [ -1, -1 ], [ -1, -1 ], wxALIGN_CENTRE, );

    $self->{answer} = Wx::TextCtrl->new( $panel, -1, '', [ -1, -1 ], [ -1, -1 ], wxTE_PROCESS_ENTER | wxTE_CENTRE, );

    $self->{set_selector} =
      Wx::ComboBox->new( $panel, -1, '', [ -1, -1 ], [ -1, -1 ], \@found, wxCB_READONLY | wxCB_SORT );

    $self->{set_status} = Wx::ListCtrl->new( $panel, -1, [ -1, -1 ], [ 200, 200 ], wxLC_LIST );

    my $activity_anim_path = catfile( dist_dir('Quiz-Flashcards'), 'ajax-loader.gif' );
    $self->{waiting_animation} = Wx::Animation->new();
    $self->{waiting_animation}->LoadFile( $activity_anim_path, wxANIMATION_TYPE_GIF );
    $self->{animator} = Wx::AnimationCtrl->new( $panel, -1, $self->{waiting_animation} );
    $self->{animator}->Play;

    # add timer
    $self->{question_timer_id} = Wx::NewId;
    $self->{question_timer}    = Wx::Timer->new( $self, $self->{question_timer_id} );
    $self->{wrong_timer_id}    = Wx::NewId;
    $self->{wrong_timer}       = Wx::Timer->new( $self, $self->{wrong_timer_id} );

    # add sizers
    $self->{set_select_sizer} = Wx::FlexGridSizer->new( 1, 0, 3, 0 );
    $self->{main_sizer}       = Wx::FlexGridSizer->new( 0, 1, 3, 0 );
    $self->{bottom_sizer} = Wx::GridSizer->new( 1, 0, 0, 0 );

    # set attributes of ui elements
    $self->{start_next_button}->Disable;
    my $font = $self->{question}->GetFont;
    $font->SetPointSize( $font->GetPointSize * 4 );
    $self->{question}->SetFont($font);
    $self->{answer}->Disable;
    $self->{correct_answer}->Hide;
    my $font2 = $self->{correct_answer}->GetFont;
    $font2->SetPointSize( $font2->GetPointSize * 2 );
    $self->{correct_answer}->SetFont($font2);

    $self->{set_status_button}->Disable;
    $self->{set_status}->Hide;
    $self->{set_status_summary}->Hide;
    $self->{animator}->Hide;

    # assign ui elements to sizers
    add_elements_to_sizer( $self->{bottom_sizer},
        [ $self->{animator}, $self->{start_next_button}, $self->{answer_time} ],
        wxALIGN_CENTER );

    add_elements_to_sizer(
        $self->{set_select_sizer},
        [ $self->{set_selector}, $self->{set_status_button} ],
        wxALIGN_CENTER
    );

    add_elements_to_sizer(
        $self->{main_sizer},
        [
            $self->{set_select_sizer}, $self->{question_description}, $self->{question},
            $self->{correct_answer},   $self->{answer}
        ],
        wxALIGN_CENTER
    );

    $self->{main_sizer}->Add( $self->{bottom_sizer}, 0, wxEXPAND );

    add_elements_to_sizer( $self->{main_sizer}, [ $self->{set_status_summary} ], wxALIGN_CENTER );
    add_elements_to_sizer( $self->{main_sizer}, [ $self->{set_status} ],         wxEXPAND );

    $panel->SetSizer( $self->{main_sizer} );
    $self->{main_sizer}->SetSizeHints($self);

    EVT_BUTTON( $self, $self->{start_next_button}, \&start_next_clicked );
    EVT_BUTTON( $self, $self->{set_status_button}, \&toggle_set_status );
    EVT_TEXT_ENTER( $self, $self->{answer}, \&check_answer );
    EVT_COMBOBOX( $self, $self->{set_selector}, \&load_set );
    EVT_TIMER( $self, $self->{question_timer_id}, \&check_answer );
    EVT_TIMER( $self, $self->{wrong_timer_id},    \&enable_start_next_button );

    $self->Center;
    $self->{answer}->SetFocus;
    
    return $self;
}

sub setup_menus {
    my ($self) = @_;

    # get menu bar up
    my $menubar = Wx::MenuBar->new();
    $self->SetMenuBar($menubar);

    # create some menu item ids
    my ( $IDM_FILE_OPEN, $IDM_FILE_CLOSE, ) = ( 10_000 .. 10_100 );

    # set up menu items
    my @file_menu_entries = (
        { id => $IDM_FILE_OPEN, label => "&Open\tCtrl-O", hint => "Open",    checkable => 0 },
        { id => '-' },
        { id => wxID_EXIT,      label => "E&xit\tCtrl-X", hint => "Exit $0", checkable => 0 },
    );

    # put them into a menu
    my $file_menu = Wx::Menu->new();
    for my $item (@file_menu_entries) {
        if ( $item->{id} eq '-' ) {
            $file_menu->AppendSeparator();
            next;
        }
        $file_menu->Append( $item->{id}, $item->{label}, $item->{hint}, $item->{checkable} );
    }

    #append the menu to the menu bar
    $menubar->Append( $file_menu, '&File' );

    # register menu events
    EVT_MENU( $self, wxID_EXIT, sub { $_[0]->Close(1) } );
}

# Event Sub-Routines
################################################################################

sub toggle_set_status {
    my ( $self, $event ) = @_;

    if ( $self->{set_status}->IsShown ) {
        $self->{set_status}->Hide;
        $self->{set_status_summary}->Hide;

        # redraw
        $self->{main_sizer}->Layout;
        $self->{main_sizer}->Fit($self);
        $self->Center;
        return;
    }

    if ( $self->{set_status_summary}->IsShown ) {
        $self->{set_status}->Show;

        # redraw
        $self->{main_sizer}->Layout;
        $self->{main_sizer}->Fit($self);
        $self->Center;
        return;
    }

    $self->update_set_status;

    $self->{set_status_summary}->Show;

    # redraw
    $self->{main_sizer}->Layout;
    $self->{main_sizer}->Fit($self);
    $self->Center;
}

sub update_set_status {
    my ( $self, $event ) = @_;
    $self->{set_status}->ClearAll;

    my %sum;
    my $i = 0;
    my $set_size = @{ $self->{set} };
    
    for my $item ( @{ $self->{set} } ) {
        $self->{set_status}
          ->InsertStringItem( $i++, "$item->{question}: $item->{certainty} %, $item->{time_to_answer} s" );
        $sum{certainty} += $item->{certainty};
        $sum{time_to_answer} += $item->{time_to_answer};
    }
    my $title = $self->{set_name};
    $title =~ s/::/ -> /;
    $self->{set_status_summary}->SetLabel(
        "$title\nCertainty = " . sprintf( "%.1f", $sum{certainty}      / $set_size )
      . " Answer Time = "      . sprintf( "%.1f", $sum{time_to_answer} / $set_size )
    );
}

sub load_set {
    my ( $self, $event ) = @_;

    my $module = $event->GetString;
    my $title  = "Quiz::Flashcards - $module";

    $module =~ s/ -> /::/;

    eval " require Quiz::Flashcards::Sets::$module; import Quiz::Flashcards::Sets::$module; ";
    die $@ if $@;

    @{ $self->{set} } = get_set();
    $self->{set_name} = $module;

    $self->setup_set_table;
    $self->load_set_table;
    $self->load_set_sounds;

    $self->{start_next_button}->SetLabel("Start");
    $self->{start_next_button}->Enable;
    $self->{start_next_button}->SetFocus;
    $self->{set_status_button}->Enable;

    $self->SetTitle($title);
    $self->update_set_status;
}

sub start_next_clicked {
    my ( $self, $event ) = @_;

    $self->select_current_question;
    $self->update_ui_for_question;
}

sub check_answer {
    my ( $self, $event ) = @_;

    $self->{question_timer}->Stop;

    my $certainty_modifier;

    if ( $self->{answer}->GetValue eq $self->{curr_question}->{answer} ) {
        my $answer_time = sprintf( "%.1f", time - $self->{curr_question}->{time_start} );
        $self->{answer_time}->SetLabel("$answer_time s");
        $certainty_modifier = 100;
        $self->{curr_question}->{time_to_answer} += .2 * ( $answer_time - $self->{curr_question}->{time_to_answer} );
        $self->{curr_question}->{time_to_answer} = sprintf( "%.1f", $self->{curr_question}->{time_to_answer} );
        $self->enable_start_next_button;
        $self->{question}->SetBackgroundColour(wxGREEN);
    }
    else {
        $self->{question}->SetBackgroundColour(wxRED);
        $certainty_modifier = 0;
        $self->{correct_answer}->Show;
        $self->{wrong_timer}->Start(1_000);
        
        
        for my $item ( @{ $self->{set} } ) {
            next if $item->{answer} ne $self->{answer}->GetValue;
            
            $item->{certainty} += .1 * ( $certainty_modifier - $item->{certainty} );
            $item->{certainty} = sprintf( "%d", $item->{certainty} );
            
            $self->update_user_data_db( $item );
            
            last;
        }
    }
    
    my $certainty_change =  .2 * ( $certainty_modifier - $self->{curr_question}->{certainty} );
    $self->{curr_question}->{certainty} += int($certainty_change + 1 * ($certainty_change <=> 0));
    $self->{curr_question}->{certainty} = sprintf( "%d", $self->{curr_question}->{certainty} );
    $self->{curr_question}->{last_seen} = int time;

    $self->update_user_data_db( $self->{curr_question} );

    $self->update_set_status;
    
    Wx::Sound->new($self->{curr_question}->{audio_file_path})->Play() if $self->{curr_question}->{audio_file_path};

    $self->{animator}->Hide;
    $self->{set_selector}->Enable;
    $self->{answer}->Disable;

    # redraw
    $self->{main_sizer}->Layout;
    $self->{main_sizer}->Fit($self);
    $self->Center;
}

# Event Helper Sub-Routines
################################################################################

sub update_user_data_db {
    my ($self, $item) = @_;

    $self->{dbh}->do( "
        REPLACE INTO $self->{set_table}
        VALUES (?,?,?,?);
    ", undef,
        $item->{id}, $item->{certainty}, $item->{time_to_answer}, $item->{last_seen} );
}


sub enable_start_next_button {
    my ($self) = @_;

    $self->{wrong_timer}->Stop;
    $self->{start_next_button}->Enable;
    $self->{start_next_button}->SetFocus;
}

sub update_ui_for_question {
    my ($self) = @_;

    $self->{question}->SetBackgroundColour(wxNullColour);
    $self->{question}->SetLabel( $self->{curr_question}->{question} );
    $self->{set_selector}->Disable;
    $self->{start_next_button}->Disable;
    $self->{start_next_button}->SetLabel("Next");
    $self->{answer}->SetValue('');
    $self->{answer}->Enable;
    $self->{answer}->SetFocus;
    $self->{answer_time}->SetLabel('');
    $self->{answer_success}->SetLabel('');
    $self->{answer_success}->SetBackgroundColour(wxNullColour);
    $self->{correct_answer}->Hide;
    $self->{correct_answer}->SetLabel( $self->{curr_question}->{answer} );
    $self->{animator}->Show;

    # redraw
    $self->{main_sizer}->Layout;
    $self->{main_sizer}->Fit($self);
    $self->Center;

    $self->{curr_question}->{time_start} = time;
    $self->{question_timer}->Start(10_000);
}

sub select_current_question {
    my ($self) = @_;
    my ( @pre_choices, @choices, $min_certainty, $max_tta );
    $min_certainty = 100;
    $max_tta       = 0;

    # find items with low certainty that we haven't seen recently
    for my $item ( @{ $self->{set} } ) {
        next if $item->{certainty} > $min_certainty;
        next if $item->{last_seen} > time - ( @{ $self->{set} } / 3 );

        @pre_choices = () if $item->{certainty} < $min_certainty;
        $min_certainty = $item->{certainty};

        push @pre_choices, $item;
    }

    # find items with a high response time
    for my $item (@pre_choices) {
        next if $item->{time_to_answer} < $max_tta;

        @choices = () if $item->{time_to_answer} > $max_tta;
        $max_tta = $item->{time_to_answer};

        push @choices, $item;
    }

    # pick random item from choices
    my $pick = int( rand($#choices) );

    $self->{curr_question} = $choices[$pick];
}

# Helper Sub-Routines
################################################################################

sub setup_database {
    use File::HomeDir;

    my $path = catfile( File::HomeDir->my_data, '.Quiz-Flashcards' );

    my $dbh = DBI->connect( "dbi:SQLite:dbname=$path", "", "" );

    $dbh->{HandleError} = sub { confess(shift) };

    $dbh->do( "
        CREATE TABLE IF NOT EXISTS settings (
            name TEXT PRIMARY KEY,
            value TEXT
        );
    " );

    #$dbh->do("
    #    INSERT OR IGNORE INTO settings
    #    VALUES ( 'font_size_question', 'original' );
    #");

    return $dbh;
}

sub setup_set_table {
    my ($self) = @_;

    $self->{set_table} = "set_$self->{set_name}";
    $self->{set_table} =~ s/::/_/;

    $self->{dbh}->do( "
        CREATE TABLE IF NOT EXISTS $self->{set_table} (
            id INTEGER NOT NULL PRIMARY KEY,
            certainty INTEGER DEFAULT 0 NOT NULL,
            time_to_answer REAL DEFAULT 10 NOT NULL,
            last_seen INTEGER DEFAULT 0 NOT NULL
        )
    " );
}

sub load_set_table {
    my ($self) = @_;

    my $hash_ref = $self->{dbh}->selectall_hashref( "SELECT * FROM $self->{set_table};", 'id' );

    for my $id ( 0 .. $#{ $self->{set} } ) {
        next if !defined $self->{set}->[$id];
        my $set_entry = $self->{set}->[$id];
        $set_entry->{id}             = $id;
        $set_entry->{certainty}      = $hash_ref->{$id}->{certainty} || 0;
        $set_entry->{time_to_answer} = $hash_ref->{$id}->{time_to_answer} || 10;
        $set_entry->{last_seen}      = $hash_ref->{$id}->{last_seen} || 0;
    }
}

sub load_set_sounds {
    my ($self) = @_;

    for my $item ( @{ $self->{set} } ) {
        next unless $item->{audiobank};
        next unless $item->{audio_file};
        
        my $ab = $item->{audiobank};
        $self->load_audiobank($ab) unless $self->{audiobanks}->{$ab};
        $item->{audio_file_path} = $self->{audiobanks}->{$ab}->{$item->{audio_file}};
    
    
    }
}

sub load_audiobank {
    my ($self, $audiobank) = @_;
    
    my $use = "require $audiobank; $audiobank->import();";

    eval $use;

    if ($@) {
        $self->{audiobanks}->{$audiobank} = 'not_available';
        return;
    }
    
    my @content_list;
    
    $use = "\@content_list = $audiobank->get_content_list;";
    eval $use;
    confess $@ if $@;
    
    my $dist = $audiobank;
    $dist =~ s/::/-/g;
    $self->{audiobank_paths}->{$audiobank} ||= dist_dir($dist);
    
    for my $file ( @content_list ) {
        $self->{audiobanks}->{$audiobank}->{$file} = catfile( $self->{audiobank_paths}->{$audiobank}, $file );
    }
}

sub add_elements_to_sizer {
    my ( $sizer, $elements, $style ) = @_;

    for my $element ( @{$elements} ) {
        $sizer->Add( $element, 0, $style );
    }
}

1;    # End of Quiz::Flashcards
