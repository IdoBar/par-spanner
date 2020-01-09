# par_spanner - Split and Annotate in Parallel
A shell wrapper to split a large input FASTA file and then execute parallel processes of NCBI BLAST or HMMscan annotations, with GNU parallel

### Requirements
The following software need to be installed and accessible from the command line (in the user `$PATH` variable):
* **GNU parallel** - can be downloaded from the official website <https://www.gnu.org/software/parallel/>, or installed using the distribution package manager (rpm, apt-get, brew, etc.)
* **awk** - the basic awk that's available with every \*NIX distribution
* NCBI **BLAST** suite - can be downloaded and installed from the NCBI [ftp repository](http://bit.ly/ncbiftp)
* **HMMER** - can be downloaded from the official website <http://hmmer.org/download.html>, along with appropriately indexed **Pfam** database, which be downloaded from the Pfam [ftp repository](bit.ly/pfamftp) and then indexed with the same version of HMMER that will be used for searching  


### Usage
Download `par_spanner.sh` and place the file in your `$PATH` (such as `~/bin/`), then run with `-h/--help` or without argument for usage message.
```
Usage: par_spanner.sh [options]
Examples: 
        par_spanner.sh -i <query.pep.fasta> -o <query.pep.blastp.outfmt6> -j 50% -N 2000 \
        --cmd "blastp -db nr -outfmt \"6 std stitle\" -evalue 1e-10"
        
        cat <query.fasta.pep> | par_spanner.sh -j 12 -N 2000 -v 0 -k -c \
        "hmmscan --cpu 4 ~/.hmmer-3.1/Pfam/Pfam-A.hmm" > query.fasta.pep.pfamout
        
Options:
         -i --in       input fasta file. If not specified will defaults to stdin [-]
         -o --out      output combined results file. If not specified will defaults to stdout [-]
         -N --entries    how many parts to break to input fasta into [default:5000]
         -j --jobs     how many parallel jobs to run
         -c --cmd      the original command to run, REQUIRED AND MUST BE QUOTED!! (escape internal quotes with \" if needed)
         -k --keep     switch to keep the temporary folder used to split and process the input file [default:false]
         -v --verbose  verbose level: 0 - none, 1 - print messages, 2 - print messages and commands (for debugging) [default:1]
         -h --help     print this help message
```
Recommended usage would be splitting the input fasta into parts of 1000-2000 entries (`-N 2000`), use `-num_threads 2` in the BLAST command to make use of BLAST's native multithreading (in its effective range), then limit jobs to a maximum of 50% of the available resources (`-j 50%`), to avoid overloading.  
For HMMER usage, just specify the command with all the optional arguments (`--cpu 4` fro example), but leave the input and output files specified beforehand with the regular `-i input.file` and `-o output.file` arguments.

### Motivation and Background
Though NCBI introduced threading in BLAST in the last decade (find citation from which version), it appears that threading is performed only at a limited stage of the analysis and that beyond 4 cores, there's little gain in performance when performing large queries against even larger databases (such as whole genome ot transcriptome annotation against NCBI nr/nt databases) [[1](http://voorloopnul.com/blog/how-to-correctly-speed-up-blast-using-num_threads/)].  
Another issue rising from performing large BLAST jobs is that in case of a server crash or failure to complete the command, it is extremely hard to track down which queries have completed and which need re-running.

An alternative approach then, is to split the input fasta into multiple files, then execute parallel separate BLAST processes of each one, while logging progress and success of each run.  
Fortunately, [GNU Parallel](https://www.gnu.org/software/parallel/parallel_tutorial.html) provides easy interface to perform such tasks:
* It can automatically split the fasta input to include a requested number of entries (while not breaking a fasta entry)
* It can launch the parallel BLAST commands for each sub-queries file (after initial preparation with `gawk`)
* It can keep a log of each process outcome, report succeeded command and re-run failed ones

### Implementation
The wrapper is written in Linux shell and should work on any POSIX-compliant system (\*NIX, MAC), with the required software (**NCBI BLAST**, **GNU parallel**, **awk**, **HMMER**, see requirments section above). Using _stdin_ and _stdout_ for optional input and output, and reporting to _stderr_, allows the tool to be used in scripts and as part of a complete analysis pipeline.  
First, an input fasta file, specified with the `-i/--in` option (or derived from _stdin_) is split into multiple sub-files (in a temp folder), each containing N fasta entries (set with the `-N/--entries` option).  
**awk** is then used to build the BLAST command for each sub-file, using the command template supplied by the user with the `-c/--cmd` option and identifying if a BLAST or HMMER command was issued (hmmscan/blast should be first at the command string, query and output files shouldn't be specified). **NOTE that the command string is a required argument and must be quoted**. If additional quotes are needed (such as when specifying custom BLAST output format), inner quotes need to be escaped with a backslash (\\"), see usage examples above.  
Finally, GNU parallel executes the commands in parallel, while keeping running information in a log file (execution time, exit value, etc.) and showing progress information (how many processes left, how many completed and estimated overall completion time).  
The number of jobs (processes) to run in parallel in controlled by the `-j/--jobs` option (same as in GNU parallel), which can be an integer, specifying the number of cores to use, or a percentage of the total available cores on the machine.  
After completion of all the sub BLAST processes, the log file is examined and the number of successfuly completed processes is compared to the number of submitted jobs. If all commands have completed successfuly, the result sub-files will be concatenated to a single output file, which is then saved to a file (whose name was given with the `-o/--out` option), or sent to _stdout_ for further processing by redirecting or piping. The script will attempt to re-run failed commands (if any).  
After successful run and verifying the the output file was saved in the requested location, the temporary folder and files will be deleted by default (unless the `-k/--keep` flag was specified).  
Additional verbosity can be specified with the `-v/--verbose` option, to report run messages (`-v 1`) or even the actual commands (`-v 2`), for debugging and troubleshooting purposes.  
Typing the tool name with the `-h/--help` option will print out the usage message. If no options is given, or if invalid input file is specified (not existent), the usage message will be printed, along with a relevant error message.  
**Note** -- each spawned BLAST job will load the database into memory, so be mindfull with memory usage and consider other users on shared servers (limit jobs to 50% of the available resources).  

### Todo
* Add additional background about multi-threaded/multi-processor BLAST
* Benchmark performance against native threaded BLAST and other implementations (MPI-BLAST, etc.)
