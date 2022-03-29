#!/usr/bin/env perl

#############################################################
## Spelling.pl 
##
## Hints generator for the NYT Spelling Bee (https://www.nytimes.com/puzzles/spelling-bee).
## 
## Uses answer lists from the analysis site https://www.nytbee.com/ and compares them
## to the player's own answers.
##
## It offers three kinds of hints:
##
## -- How many more words of various lengths remain?
## -- How many more words remain that beginning with each letter?
## -- How many missing words remain in between the alread-found answers?
## -- How many more words remain that begin with various two-letter pairs?
##
## But the script is flexible enough to add other hints that people may suggest.
##
## By Bob King, 2021
#############################################################

use Modern::Perl;
use Mojo::UserAgent;
use DateTime;
use Sort::Key::Natural qw(natsort);
use List::MoreUtils qw(first_index);
use Data::Dumper;

# Tracks how many hints you've gotten so far
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

sub setup {
    
    # The words the user has successfully guessed. The user must save these in the selected file
    
    my %my_words = ( filename     => 'lib/words.txt',    # Where to find this file
                     find_methods => [ \&read_file ],    # How to find the words (the only way is to read the file)
                   );
		   
    # The answers to today's puzzle
    
    my %answers  = ( filename     => add_date_to_filename( 'lib/answers.txt' ),  # Where to find this file
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
    # The hints with use the "find missing" compare type also have a criterion (these are all anonymous
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

sub lookup {
    
    my @lists = @_;
    my @results = map { get_list( $_ ) } @lists;
    
    return @results;
    
    }

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
            $result =~ s/\s//g;
            push @fixed_results, lc $result if $result gt '';
        
            }
            
        }
                
    return @fixed_results; 
            
    }       
        
########################################################################

sub download_data {

    my $params   = shift;
    my $outfile  = $params->{ filename };
    my $site     = $params->{ site };
    my $selector = $params->{ selector };
    my $ua       = $params->{ ua };
    my @results;
    
    say "Downloading words from $site\n";
    
    my $answers = $ua->get( $site )->result->dom->find( $selector );

	for my $answer( @$answers ) {

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

sub add_date_to_filename {
    
    my $file_name_old = shift;
    $file_name_old =~ /^(.*)\.(.*)$/;
    
    my $dt = DateTime->now;
    my $today = join( "-", ( $dt->year, $dt->month, $dt->day ) );

    my $file_name_new = "$1$today.$2";
    return $file_name_new;

    }


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

sub find_before_and_after {
    
    my %params = @_;

    my $function                      = $params{ function };
    my ( $words_list, $answers_list ) = @{ $params{ lists } };
    my $place_in_words                = $function->( $words_list );
    my $place_in_answers              = $function->( $answers_list );
    my $word_word                     = sub { return $_[0] == 1 ? 'word' : 'words' };
    my ( @before_and_after );
    

    for my $this_word( @$words_list ) {
        
        my $position  = $place_in_words->{ $this_word };
        my $next_word = $words_list->[ $position + 1 ] || '**END**';

        #Make sure the current word and the next one both exist in the answer list
        #If they don't, return an error
        for my $word( $this_word, $next_word ) {
            
            unless ( defined $place_in_answers->{ $word } || $word eq '**END**'  ) {
            
                push @before_and_after, "\n\n\t***Invalid word in list: '$word' is not a valid answer!";
                return @before_and_after;
            
                }
            
            }
        
        #Special case #1: Is this the first word in our list?
        #If so, is it also the first word in the answer list?
        #Or do some answers come before it?
        
        if ( $position == 0 ) {
            
            my $gap = $place_in_answers->{ $this_word };
            
            if ( $gap == 0 ) {
                
                    push @before_and_after, "*** $this_word is the first word ***"; 
                
                } else {
                    
                    push @before_and_after, "$gap " . $word_word->( $gap ) . " before $this_word";
                    
                }
            
            }
            
        #Special case #2: Have we come to the end of our word list?
        #If so, is our last word also the last answer, or are there answers after it?
        
        if ( $next_word eq '**END**') {
            
            my $gap = $#{$answers_list} - $place_in_answers->{ $this_word };
            
            if ( $gap == 0 ) {            
                        
                push @before_and_after, "*** $this_word is the last word ***\n";
               
                } else {
                
                push @before_and_after, "$gap " . $word_word->($gap) . " after $this_word";
       
                }
            
            #We've run out of special cases, so treat this as an ordinary word.
            #Find out how many answers exist between this and our next word
            #But don't report any zeroes
            
            } else {
            
                my $gap = $place_in_answers->{ $next_word } - $place_in_answers->{ $this_word } - 1;

                push @before_and_after, "$gap " . $word_word->($gap) . " between $this_word and $next_word" 
                    unless $gap == 0;
 
                }
 
            }
    
    return @before_and_after;
    
    
    }

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
