#!/usr/bin/env perl

########################################################################
## Spelling.pl 
##
## Hints generator for the NYT Spelling Bee (https://www.nytimes.com/puzzles/spelling-bee).
## 
## Uses answer lists from the analysis site https://www.nytbee.com/ and compares them
## to the player's own answers.
##
## It offers four kinds of hints:
##
## -- How many more words of various lengths remain?
## -- How many more words remain that beginning with each letter?
## -- How many missing words remain in between the alread-found answers?
## -- How many more words remain that begin with various two-letter pairs?
##
## But the script is flexible enough to add other hints that people may suggest.
##
## By Bob King, 2021
########################################################################

use Modern::Perl;
use Mojo::UserAgent;
use DateTime;
use Sort::Key::Natural qw(natsort);
use List::MoreUtils qw(first_index);

# Tracks how many hints you've gotten so far (this resets every time you restart the script)
my $counter;

# Sets up basic info (configurations for your own words and the downloaded answers, plus the preset hint types)
my ( $my_words, $answers, $hint_types ) = setup();

# Grabs your words list. Also downloads the answers from NYTBee (or, if they've already been downloaded,
# pulls them from the cached file)
my ( $words_list, $answers_list ) = lookup( $my_words, $answers );

# Cycles through the hint types and asks one at a time; ends the session if we're done
for my $hint_type( @$hint_types ) {
    
    $counter++;
    
    my $hint = find_hints( $hint_type, 
                           $words_list, 
                           $answers_list, 
                           $counter, 
                           scalar @$hint_types );      # length of the hint_types arrayref
    
    last if $hint eq 'done';

    }

exit;

#######################################################################
# Configuration of the main hashes and lists that the script depends on.
########################################################################

sub setup {
    
    # The words the user has successfully guessed. The user must save these in the selected file
    
    my %my_words = ( filename     => 'lib/words.txt',    # Where to find this file
                     find_methods => [ \&read_file ],    # How to find the words (the only way is to read the file)
                   );
		   
    # The answers to today's puzzle
    
    my %answers  = ( filename     => add_date_to_filename( 'lib/answers.txt' ),  # Where to find this file (which
                                                         			 # will have today's date in the name)
                     find_methods => [ \&read_file, \&download_data ],	# How to find the answers (two ways:
		                                                        # read the file, or download them if the
									# file doesn't exist yet)
                     site         => 'https://www.nytbee.com/',	# Site where today's answers live             
                     selector     => '#main-answer-list > .column-list > li',	# CSS selector
                     ua           => Mojo::UserAgent->new,			# We're using Mojo's useragent
                   );
               
    # This next list defines the hint types that we will try one at a time. 
    #
    # Each hint has its own "compare type" (it will either find the number of missing words that meet 
    # some criterion, or it will find the number of missing words that exist before or after the words 
    # the user has found), as well as a "function" (which either counts the words that qualify or determines
    # the found words' relative position in the full answer list).
    #
    # The hints that use the "find missing" compare type also have a criterion (these are all anonymous
    # functions, but of course function references would work too), along with a phrase to help the user
    # figure out what the hint is getting at.
    
    my @hint_types = ( 
                       # Lengths of missing words
                       { compare_type => \&find_missing,
                         function     => \&frequency,
                         criterion    => sub { return length( $_[0] ) },
                         phrase       => 'Number of letters',
                       },

                       # Missing words start with these letters
                       { compare_type => \&find_missing,
                         function     => \&frequency,
                         criterion    => sub { return substr $_[0], 0, 1 },
                         phrase       => 'Words begin with',
                       },

                       # How many answers before, after or between our words
                       { compare_type => \&find_before_and_after,
                         function     => \&word_positions,
                       },

                       # Missing words start with these 2-letter combos
                       { compare_type => \&find_missing,
                         function     => \&frequency,
                         criterion    => sub { return substr $_[0], 0, 2 },
                         phrase       => 'Words begin with',
                       },
                     );
           
    return ( \%my_words, \%answers, \@hint_types );
        
    }

########################################################################
# Given a list of word or answer lists, look up each one in turn, 
# then return them all at once.
########################################################################

sub lookup {
    
    my @lists = @_;
    my @results = map { get_list( $_ ) } @lists;
    
    return @results;
    
    }

########################################################################
# Given a specific list, look it up using the predefined list of methods.
# If the first method succeeds, return it. If not, keep trying.
# Return an empty list if nothing works.
########################################################################

sub get_list {
    
    my $list = shift;
    my $find_methods = $list->{ find_methods };
    
    for my $method( @$find_methods ) {
        
        my @results = $method->( $list );
        return \@results if @results; 
        
        }
        
    return [];
        
    }

########################################################################
# Read words from a file, if it exists. 
# Also sort them and make them all lowercase.
########################################################################

sub read_file {
    
    my $params = shift;
    my $infile = $params->{ filename };
    my ( @results, @fixed_results );
    
    if ( -e $infile ) {
        
        say "Reading words from $infile.\n";
        
        open my $fh, '<', $infile or warn "Cannot open $infile: $!\n";
        
        @results = <$fh>; 
        
        for my $result( sort @results ) {
            
            chomp $result;					
            $result =~ s/\s//g;		# Cut out extra spaces
            push @fixed_results, lc $result if $result gt '';
        
            }
            
        }
                
    return @fixed_results; 
            
    }       
        
########################################################################
# Download words from a website, using CSS selectors, and save 
# them to a file.
########################################################################

sub download_data {

    my $params   = shift;
    my $outfile  = $params->{ filename };
    my $site     = $params->{ site };
    my $selector = $params->{ selector };
    my $ua       = $params->{ ua };
    my @results;			# List for storing the words we find 
    
    say "Downloading words from $site\n";
    
    my $answers = $ua->get( $site )->result->dom->find( $selector );

	for my $answer( @$answers ) {

		# Strip away html coding for bold type (used for pangrams) 
		if ( $answer =~ /<strong>(.*)<\/strong>/ ) {

			$answer = $1;

		} else {

			$answer = $answer->text;
            
			} 

        $answer =~ s/\s*//g;
        
        if ( $answer gt '' ) {
            
            push @results, lc $answer;
            
            }    
        
        }
    
    @results = sort @results;
    
    open my $fh, '>', $outfile or die "Cannot write to $outfile: $!\n";
    say $fh $_ for @results; 
    
    return @results;
    
    }

########################################################################
# Convert 'answers.txt' to 'answersYYYY-MM-DD.txt'
########################################################################

sub add_date_to_filename {
    
    my $file_name_old = shift;
    $file_name_old =~ /^(.*)\.(.*)$/;
    
    my $dt = DateTime->now;
    my $today = join( "-", ( $dt->year, $dt->month, $dt->day ) );

    my $file_name_new = "$1$today.$2";
    return $file_name_new;

    }

########################################################################
# Count the frequency of words ('items') in a list, using the set criterion
########################################################################

sub frequency {
    
    my ( $list, $criterion ) = @_;
    my %count;

    for my $item( @$list ) {
        
        my $selection = $criterion->( $item );
        $count{ $selection }++ if $item gt '';
        
        }
        
    return \%count;

    }
    
########################################################################
# Figure out where a given word exists in an alphabetized list of words.
# Note: first_index function is provided by List::MoreUtils
########################################################################

sub word_positions {
    
    my $list = shift;
    my %positions_list;

    for my $item( @$list ) {
      
        next unless $item gt '';
        $positions_list{ $item } = first_index { $_ eq $item } @$list;
        
        }

    return \%positions_list;
    
    }
    
########################################################################
# Calculate the number of missing words (i.e., how many answers the users
# has not found yet), based on criteria such as word length or the initial letter.
# Assemble this information into a list of phrases that will make up the hint.
# Note: natsort function is provided by Sort::Key::Natural
########################################################################

sub find_missing {
    
    my %params    = @_;
    my $function  = $params{ function };
    my $criterion = $params{ criterion };
    my $phrase    = $params{ phrase };
    my ( $words_list, $answers_list ) = @{ $params{ lists } };
    
    my ( $word_counts, $answer_counts ) 
        = map { $function->( $_, $criterion ) } ( $words_list, $answers_list );
    
    my ( @missing_list, @sorted_answers );
    
    for my $tier( natsort keys %$answer_counts ) {
        
        my $total_words = $answer_counts->{ $tier };
        my $found_words = $word_counts->{ $tier } || 0;
        
        my $missing_words  = $total_words - $found_words;
        my $missing_phrase = "$phrase: $tier -- $missing_words missing";
        
        push @missing_list, $missing_phrase unless $missing_words == 0;
        
        }   
       
    return @missing_list;
    
    }

########################################################################
# This function counts how many unfound answers exist before, after and
# in between the words that the user has found. It does this by comparing
# the list of the users' words against the full answer list, then assembling
# that info into phrases that make up the hint.
#
# Note: We use $word_word to ensure that the numbers and verbs in each phrase
# agree grammatically ("1 word" but "2 words," "3 words," etc.).
########################################################################

sub find_before_and_after {
    
    my %params = @_;

    my $function                      = $params{ function };
    my ( $words_list, $answers_list ) = @{ $params{ lists } };
    my $place_in_words                = $function->( $words_list );
    my $place_in_answers              = $function->( $answers_list );
    my $word_word                     = sub { return $_[0] == 1 ? 'word' : 'words' };
    my ( @before_and_after );
    
    # Go through the users' words one at a time, figure out where they exist in the full
    # answer list, then start figuring out where the missing words are.

    for my $this_word( @$words_list ) {
        
	# Is this the user's last word? If not, what's their next word?
	
        my $position  = $place_in_words->{ $this_word };
        my $next_word = $words_list->[ $position + 1 ] || '**END**';

        # Make sure the user's current word and the next one both exist in the answer list.
        # If either one of them doesn't, return an error message.
	
        for my $word( $this_word, $next_word ) {
            
            unless ( defined $place_in_answers->{ $word } || $word eq '**END**'  ) {
            
                push @before_and_after, "\n\n\t***Invalid word in list: '$word' is not a valid answer!";
                return @before_and_after;
            
                }
            
            }
        
        # Special case #1: Is this the first word in the user's list?
        # If so, is it also the first word in the answer list?
        # Or do some answers come before it?
        
        if ( $position == 0 ) {
            
            my $gap = $place_in_answers->{ $this_word };
            
            if ( $gap == 0 ) {
                
                    push @before_and_after, "*** $this_word is the first word ***"; 
                
                } else {
                    
                    push @before_and_after, "$gap " . $word_word->( $gap ) . " before $this_word";
                    
                }
            
            }
            
        # Special case #2: Have we come to the end of our word list?
        # If so, is the user's last word also the last answer, or do answers exist after it?
        
        if ( $next_word eq '**END**') {
            
            my $gap = $#{$answers_list} - $place_in_answers->{ $this_word };
            
            if ( $gap == 0 ) {            
                        
                push @before_and_after, "*** $this_word is the last word ***\n";
               
                } else {
                
                push @before_and_after, "$gap " . $word_word->($gap) . " after $this_word";
       
                }
            
            # We've run out of special cases, so treat this as an ordinary word.
            # Find out how many answers exist between this and the user's next word.
            # But don't report any zeroes.
            
            } else {
            
                my $gap = $place_in_answers->{ $next_word } - $place_in_answers->{ $this_word } - 1;

                push @before_and_after, "$gap " . $word_word->($gap) . " between $this_word and $next_word" 
                    unless $gap == 0;
 
                }
 
            }
    
    return @before_and_after;
    
    
    }

########################################################################
# This is the function that makes the whole thing work: 
#
# 1) Find the next set of hints using the hint type, word list, answer 
# list and compare type that this function has been provided.
#
# 2) Tell the hints to the user.
#
# 3) Keep track of how many hints the user has gotten so far, 
# and return "done" if we've reached the end. Also return "done" 
# if the user doesn't want any more hints.
#
# And that's it! We're done.
########################################################################

sub find_hints {
    
    my ( $hint_type, $words_list, $answers_list, $counter, $number_of_hints ) = @_;
    my $compare = $hint_type->{ compare_type };
        
    my @hints = $compare->( function  => $hint_type->{ function }, 
                            criterion => $hint_type->{ criterion },
                            phrase    => $hint_type->{ phrase } || '',
                            lists     => [ $words_list, $answers_list ],
                          ); 
    
    say $_ for @hints;
    return 'done' if $counter == $number_of_hints;    
    
    print "\nDo need more hints (y/n?) ";
    my $answer = <STDIN>;
    return 'done' unless $answer =~ /^y.*/i;
    
    say "\n***\n";
    
    return 'continue';
    
    }
