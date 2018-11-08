#!/bin/bash

_usage() {
cat <<EOF
$*
        Usage: $0 <[options]>
	Examples: 
		par_spanner.sh -i <query.pep.fasta> -o <query.pep.blastp.outfmt6> -j 50% -N2000 \
		--cmd "blastp -db nr -outfmt \"6 std stitle\" -evalue 1e-10"

		cat <query.fasta> | par_spanner.sh -j 12 -N2000 -v 0 -k -c \
		"hmmscan --cpu 4 ~/.hmmer-3.1/Pfam/Pfam-A.hmm" > query.fasta.pfam.domtblout

	Options:
		 -i --in       input fasta file. If not specified will use stdin [-]
		 -o --out      output combined results file. If not specified will use stdout [-]
		 -N --entries    how many parts to break to input fasta into [default:5000]
		 -j --jobs     how many parallel jobs to run
		 -c --cmd      the original command to run, REQUIRED AND MUST BE QUOTED!! (escape internal quotes with \" if needed)
		 -k --keep     switch to keep the temporary folder used to split and process the input file [default:false]
		 -v --verbose  verbose level: 0 - none, 1 - print messages, 2 - print messages and commands (for debugging) [default:1]
		 -h --help     print this help message

EOF
}
if [ $# = 0 ]; then _usage "  >>>>>>>> no options given " >&2 ; exit 1 ; fi


# [ $# -ge 1 -a -f "$1" ] && input="$1" || input="-"
# Define these according to the run

# For HMMER
# NOTE: This requires GNU getopt.  On Mac OS X and FreeBSD, you have to install this
# separately; see below.
if ! TEMP=`getopt -o i:o:N:j:c:kv:h --long in:,out:,entries:,jobs:,cmd:,keep,verbose:,help -n 'par_spanner' -- "$@"`
then
    # something went wrong, getopt will put out an error message for us
    _usage >&2
    exit 1
fi
# if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

VERBOSE=1
JOBS=32
NPARTS=5000
WORKDIR=`pwd`
# Use wildcards or specify an exact input fasta filename below (should be in your current working directory)
INPUT="-"
OUTFILE="-"
DATE=`date +%d_%m_%Y`
KEEP=false
# CMD='blastp -db nr -outfmt \"6 std stitle staxids sscinames sskingdom\" -max_target_seqs 1 -max_hsps 1 -evalue 1e-10'
#CMD=`printf "hmmscan --cpu %s --domtblout \%s/\%s.pfam.domtblout ~/.hmmer-3.1/Pfam/Pfam-A.hmm \%s > \%s/\%s_pfam.log",$NCPUS`
# update PREFIX to your liking (a nice, short descriptive name of your split analysis)
TMPLOC=$( mktemp -d --tmpdir=./ ) # to create a temporary folder in the current path
PREFIX="parallel_split_"$DATE
BLAST=0

CMD=false
while true; do
  case "$1" in
    -i | --in ) INPUT="$2" ; shift 2 ;;
    -o | --out ) OUTFILE="$2" ; shift 2 ;;
    -N | --entries ) NPARTS="$2" ; shift 2 ;;
    -j | --jobs ) JOBS="$2" ; shift 2 ;;
    -c | --cmd ) CMD="$2" ; shift 2 ;;
    -k | --keep ) KEEP=true ; shift ;;
    -v | --verbose ) VERBOSE="$2" ; shift 2 ;;
    -h | --help ) _usage ; shift ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

# Convert verbose to numeric
VERBOSE=$(( VERBOSE  + 1 - 1 ))

# Check valid input (file or stdin):
if ! [[ -e "$INPUT" || "$INPUT" = "-" ]]; then
        _usage "  >>>>>>>> no valid input file given ($INPUT) "
        exit 1
fi

if [[ "$INPUT" = "-" ]]; then
	INPUT_FASTA="$PREFIX.fasta"
	cat "$INPUT" > "$TMPLOC"/"$INPUT_FASTA"
else
	INPUT_FASTA="$INPUT"
	cp $INPUT_FASTA "$TMPLOC"/"$INPUT_FASTA"
	
fi
# Check mandatory parameters:
if ! [[ "$CMD" = false ]]; then
     if [[ $(echo $CMD | awk '{print match($1, "blast")}') > 0 ]]; then 
        BLAST=1
        # For blast, set
        SUFFIX="outfmt6"
     fi
     if [[ $(echo $CMD | awk '{print match($1, "hmm")}') > 0 ]]; then 
        BLAST=2
        # For hmm, set
        SUFFIX="pfam.domtblout"
     fi
     if [[ $BLAST = 0 ]]; then
         _usage "  >>>>>>>> no valid command given (missing blast or hmm command)"
         exit 1
     fi
else
    _usage "  >>>>>>>> no valid command given "
         exit 1
fi 




# verbose - print commands
if [[ $VERBOSE = 2 ]]; then  set -v; fi
#SUFFIX="pfam.domtblout"
# mkdir $PREFIX 2>/dev/null
cd $TMPLOC # $PREFIX
cat $INPUT_FASTA | parallel --gnu -kN$NPARTS --no-run-if-empty --recstart '>' --pipe "cat > $INPUT_FASTA.part{#}"
# remove empty files:
# find . -size 0 -name "$INPUT_FASTA.part*" | xargs rm
# Add a trailing '0' to parts 1-9 (to be able to sort the files):
rename 's/part([0-9])/part0$1/' $INPUT_FASTA.part?


# Create the parallel commands (your blast command goes in the printf("...") part below.
# %s are placements for strings that are kept in the variables at the end of the function($1 - file to process from awk, SUBDIR and FILENAME for output folder and file respectively)
#find `pwd` -maxdepth 1 -name "*part*" | awk -v PRE="$PREFIX" -v CPUS="$NCPUS" -v SUF="$SUFFIX" '{n=split($1,a,"/"); SUBDIR=PRE"_results" ;FILENAME=a[n]; "mkdir "SUBDIR" 2>&-" | getline ; printf "hmmscan --cpu %s --domtblout %s/%s.%s ~/.hmmer-3.1/Pfam/Pfam-A.hmm %s > %s_%s_pfam.log\n",CPUS, SUBDIR, FILENAME, SUF, $1, PRE, FILENAME}' > $PREFIX.cmds

find `pwd` -maxdepth 1 -name "*part*" | awk -v BLAST=$BLAST -v CMD="$CMD" -v PRE="$PREFIX" -v SUF="$SUFFIX" '
    {n=split($1,a,"/"); SUBDIR=PRE"_results" ;FILENAME=a[n]; "mkdir "SUBDIR" 2>&-" | getline ; 
    if (BLAST == 1) 
        {printf("%s -query %s > %s/%s.%s\n", CMD, $1, SUBDIR, FILENAME, SUF)} 
    else if (BLAST == 2) 
        {y=split(CMD,h); TMPCMD=CMD; STR=sprintf("%s --domtblout %s/%s.%s",h[1], SUBDIR,FILENAME,SUF); sub(h[1], STR, TMPCMD);
        printf("%s %s > /dev/null\n", TMPCMD, $1)}}' > $PREFIX.cmds

CMDNUM=$( wc -l < ./$PREFIX.cmds )
# Finally, for running the blastp commands in parallel:
sort $PREFIX.cmds | parallel --gnu --progress -j$JOBS --joblog ./$PREFIX.parallel.log

# check log file and produce to err file:
awk -F"\t" 'NR>1{if ($7>0){print $9}}' ./$PREFIX.parallel.log > ./$PREFIX.failed_cmds
awk -F"\t" 'NR>1{if ($7==0){print $9}}' ./$PREFIX.parallel.log > ./$PREFIX.successful_cmds
FAILED=$( wc -l < ./$PREFIX.failed_cmds )
SUCCEED=$( wc -l < ./$PREFIX.successful_cmds )

# verbose - print commands

if [[ "$FAILED" > 0 || "$SUCCEED" < "$CMDNUM" ]] ; then
    if [[ "$VERBOSE" > 0 ]] ; then
        set +v
        >&2 printf -v int "!! %i commands failed:\n" $FAILED
        >&2 cat ./$PREFIX.failed_cmds
        if [[ "$VERBOSE" = 2 ]]; then set -v; fi # verbose - do not echo print commands
    fi
    read -e -p ">> Retry running the failed commands? (press enter for Yes, or type N/n): " -i "Yes" RETRY
    if [[ "$RETRY" = "Yes" ]]; then
        parallel --gnu --progress --retry-failed -j$JOBS --joblog ./$PREFIX.parallel.log
        awk -F"\t" 'NR>1{if ($7==0){print $9}}' ./$PREFIX.parallel.log > ./$PREFIX.successful_cmds_retry
        RETRY_OK=$( wc -l ./$PREFIX.successful_cmds_retry )
        if [[ "$RETRY_OK" = "$CMDNUM" ]] ; then
            if [[ "$VERBOSE" > 0 ]]; then set +v;  >&2 echo "All command completed successfuly in second attempt, combining output file." ; fi
            if [[ "$VERBOSE" = 2 ]]; then set -v; fi # verbose - do not echo print commands
        fi
    else
        >&2 printf "!! Some failed commands remains, please check log file (%s.parallel.log)\n" $PREFIX
        >&2 printf "## Combining successful commands into file (%s)\n" "$INPUT_FASTA".$SUFFIX
        touch "$INPUT_FASTA".$SUFFIX
        find $PREFIX"_results" -type f -name "$INPUT_FASTA.part*.$SUFFIX" | xargs -I '{}' cat '{}' >> "$INPUT_FASTA".$SUFFIX
        exit 1
    fi
else
    if [[ "$VERBOSE" > 0 ]]; then set +v; >&2 echo "## All commands completed successfuly, combining output file."; fi
    if [[ "$VERBOSE" = 2 ]]; then set -v; fi # verbose - echo commands
    # Combine the output files:
    TMPFILE="$INPUT_FASTA.$SUFFIX"
    touch "$TMPFILE"
    find $PREFIX"_results" -type f -name "$INPUT_FASTA.part*.$SUFFIX" | xargs -I '{}' cat '{}' >> "$TMPFILE"
    # check that the combined output file exists, and that all commands finished successfuly only then:
    if [[ -f "$TMPFILE" ]]; then
        if [[ "$OUTFILE" = "-" ]]; then
            cat "$TMPFILE"
            # exit 0
        else
            cp "$TMPFILE" "$WORKDIR/$OUTFILE"
            if [[ "$VERBOSE" > 0 ]] ; then set +v; >&2 printf "## Combined output file can be found at %s\n" "$WORKDIR/$OUTFILE"; fi
            if [[ "$VERBOSE" = 2 ]] ; then set -v; fi
        fi
        if [[ "$KEEP" = false ]]; then
	    if [[ "$VERBOSE" > 0 ]] ; then set +v; >&2 printf "## Returning to working directory and removing temporary files and folders\n"; fi
            if [[ "$VERBOSE" = 2 ]] ; then set -v; fi
            cd "$WORKDIR"
            rm -r $TMPLOC
	else
            cd "$WORKDIR"
            if [[ "$VERBOSE" > 0 ]] ; then set +v; >&2 printf "## Type <rm -r %s> to remove the folder containing the temporary files\n" "$TMPLOC"; fi
            if [[ "$VERBOSE" = 2 ]] ; then set -v; fi
        fi
    else
        if [[ "$VERBOSE" > 0 ]] ; then set +v; >&2 printf "!! Could not find final output, check in temporary folder\n" "$TMPLOC"; fi
        if [[ "$VERBOSE" = 2 ]] ; then set -v; fi
        exit 1
    fi
fi
exit 0
##
