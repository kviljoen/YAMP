#!/usr/bin/env nextflow
/*
========================================================================================
               M E T A G E N O M I C S   P I P E L I N E
========================================================================================
 METAGENOMICS NEXTFLOW PIPELINE ADAPTED FROM YAMP FOR UCT CBIO
 
----------------------------------------------------------------------------------------
*/

/**
	Prints help when asked for
*/

def helpMessage() {
    log.info"""
    ===================================
     uct-yamp  ~  version ${params.version}
    ===================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run uct-cbio/uct-yamp --reads '*_R{1,2}.fastq.gz' -profile uct_hex
    Mandatory arguments:
      --reads                       Path to input data (must be surrounded with quotes)
      -profile                      Hardware config to use. uct_hex OR standard
      
    BBduk trimming options:
      --qin			    Input quality offset: 33 (ASCII+33) or 64 (ASCII+64, default=33
      --kcontaminants		    Kmer length used for finding contaminants, default=23	
      --phred			    Regions with average quality BELOW this will be trimmed, default=10 
      --minlength		    Reads shorter than this after trimming will be discarded, default=60
      --mink			    Shorter kmers at read tips to look for, default=11 
      --hdist			    Maximum Hamming distance for ref kmers, default=1            

    BBwrap parameters for decontamination:	
      --mind			   Approximate minimum alignment identity to look for, default=0.95
      --maxindel		   Longest indel to look for, default=3
      --bwr			   Restrict alignment band to this, default=0.16
	
    MetaPhlAn2 parameters: 
      --bt2options 		   Presets options for BowTie2, default="very-sensitive"
      
    Strainphlan parameters (optional):
      --strain_of_interest	   Strain for tracking across samples in metaphlan2 format e.g. s__Bacteroides_caccae
      
    Other options:
      --keepCCtmpfile		    Whether the temporary files resulting from MetaPhlAn2 and HUMAnN2 should be kept, default=false
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.
      
     Help:
      --help                        Will print out summary above when executing nextflow run uct-cbio/uct-yamp --help                                    
    """.stripIndent()
}
	
/*
 * SET UP CONFIGURATION VARIABLES
 */

// Configurable variables
params.name = false
//params.project = false
params.email = false
params.plaintext_email = false
params.strain_of_interest = false
params.strain_reference_genome = false

// Show help emssage
params.help = false
if (params.help){
    helpMessage()
    exit 0
}
 

if (params.qin != 33 && params.qin != 64) {  
	exit 1, "Input quality offset (qin) not available. Choose either 33 (ASCII+33) or 64 (ASCII+64)" 
}   

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}

// Returns a tuple of read pairs in the form
// [sample_id, forward.fq, reverse.fq] where
// the dataset_id is the shared prefix from
// the two paired FASTQ files.
Channel
    .fromFilePairs( params.reads )
    .ifEmpty { error "Cannot find any reads matching: ${params.reads}" }
    .into { ReadPairsToQual; ReadPairs }

//Input reference files validation:
//BDUK reference files:
Channel
    .fromPath(params.adapters)
    .ifEmpty { exit 1, "BBDUK adapter file not found: ${params.adapters}"  }
    .into { adapters_ref }
Channel
    .fromPath(params.artifacts)
    .ifEmpty { exit 1, "BBDUK adapter file not found: ${params.artifacts}"  }
    .into { artifacts_ref }
Channel
    .fromPath(params.phix174ill)
    .ifEmpty { exit 1, "BBDUK phix file not found: ${params.phix174ill}"  }
    .into { phix174ill_ref }
    
//process decontaminate validate reference file
Channel
    .fromPath(params.refForeignGenome, type: 'dir')
    .ifEmpty { exit 1, "BBDUK foreign genome reference file not found: ${params.refForeignGenome}"  }
    .into { refForeignGenome_ref }

//metaphlan bowtie reference DB
Channel
    .fromPath(params.bowtie2db, type: 'dir')
    .ifEmpty { exit 1, "Bowtie2 DB reference file not found: ${params.bowtie2db}"  }
    .into { bowtie2db_ref }

//mpa_pkl send to both metaphlan and strainphlan
Channel
    .fromPath(params.mpa_pkl)
    .ifEmpty { exit 1, "--mpa_pkl file for metaphlan/strainphlan not found: ${params.mpa_pkl}" }
    .into { mpa_pkl_m; mpa_pkl_s }
    
//humann2 reference files
Channel
    .fromPath(params.chocophlan, type: 'dir')
    .ifEmpty { exit 1, "Chocophlan reference file for humann2 not found: ${params.chocophlan}" }
    .into { chocophlan_ref }
Channel
    .fromPath(params.uniref, type: 'dir')
    .ifEmpty { exit 1, "Uniref reference file for humann2 not found: ${params.chocophlan}" }
    .into { uniref_ref }
        
//Strainphlan_2 ref files
Channel
    .fromPath(params.metaphlan_markers, type: 'dir')
    .ifEmpty { exit 1, "Metaphlan markers file for strainphlan not found: ${params.metaphlan_markers)}" }
    .into { MM }
    

// Header log info
log.info "==================================="
log.info " uct-yamp  ~  version ${params.version}"
log.info "==================================="
def summary = [:]
summary['Run Name']     = custom_runName ?: workflow.runName
summary['Reads']        = params.reads
summary['OS']		= System.getProperty("os.name")
summary['OS.arch']	= System.getProperty("os.arch") 
summary['OS.version']	= System.getProperty("os.version")
summary['javaversion'] = System.getProperty("java.version") //Java Runtime Environment version
summary['javaVMname'] = System.getProperty("java.vm.name") //Java Virtual Machine implementation name
summary['javaVMVersion'] = System.getProperty("java.vm.version") //Java Virtual Machine implementation version
//Gets starting time		
sysdate = new java.util.Date() 
summary['User']		= System.getProperty("user.name") //User's account name
summary['Max Memory']     = params.max_memory
summary['Max CPUs']       = params.max_cpus
summary['Max Time']       = params.max_time
summary['Output dir']     = params.outdir
summary['Working dir']    = workflow.workDir
summary['Container']      = workflow.container
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Current home']   = "$HOME"
summary['Current user']   = "$USER"
summary['Current path']   = "$PWD"
summary['Script dir']     = workflow.projectDir
summary['Config Profile'] = workflow.profile
if(params.email) {
    summary['E-mail Address'] = params.email
}
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="

		
/*
 *
 * Step 1: FastQC (run per sample)
 *
 */

process runFastQC {
    cache 'deep'
    tag { "rFQC.${pairId}" }

    publishDir "${params.outdir}/FilterAndTrim", mode: "copy"

    input:
        set pairId, file(in_fastq) from ReadPairsToQual

    output:
        file("${pairId}_fastqc/*.zip") into fastqc_files

    """
    mkdir ${pairId}_fastqc
    fastqc --outdir ${pairId}_fastqc \
    ${in_fastq.get(0)} \
    ${in_fastq.get(1)}
    """
}

process runMultiQC{
    cache 'deep'
    tag { "rMQC" }

    publishDir "${params.outdir}/FilterAndTrim", mode: 'copy'

    input:
        file('*') from fastqc_files.collect()

    output:
        file('multiqc_report.html')

    """
    multiqc .
    """
}

/*
 *
 * Step 2: De-duplication (run per sample)
 *
 */

process dedup {
	cache 'deep'
	tag { "dedup.${pairId}" }
	
	input:
	set val(pairId), file(reads) from ReadPairs

	output:
	set val(pairId), file("${pairId}_dedupe_R1.fq"), file("${pairId}_dedupe_R2.fq") into totrim, topublishdedupe

	script:
        markdup_java_options = (task.memory.toGiga() < 8) ? ${params.markdup_java_options} : "\"-Xms" +  (task.memory.toGiga()/10 )+"g "+ "-Xmx" + (task.memory.toGiga() - 8)+ "g\""

	"""
	clumpify.sh ${markdup_java_options} in1="${reads[0]}" in2="${reads[1]}" out1=${pairId}_dedupe_R1.fq out2=${pairId}_dedupe_R2.fq \
	qin=$params.qin dedupe subs=0 threads=${task.cpus}
	
	"""
}


/*
 *
 * Step 3: BBDUK: trim + filter (run per sample)
 *
 */

process bbduk {
	cache 'deep'
	tag{ "bbduk.${pairId}" }
	
	input:
	set val(pairId), file("${pairId}_dedupe_R1.fq"), file("${pairId}_dedupe_R2.fq") from totrim
	file adapters from adapters_ref
	file artifacts from artifacts_ref
	file phix174ill from phix174ill_ref

	output:
	set val(pairId), file("${pairId}_trimmed_R1.fq"), file("${pairId}_trimmed_R2.fq"), file("${pairId}_trimmed_singletons.fq") into todecontaminate
	set val(pairId), file("${pairId}_trimmed_R1.fq"), file("${pairId}_trimmed_R2.fq") into filteredReadsforQC

	script:
	markdup_java_options = (task.memory.toGiga() < 8) ? ${params.markdup_java_options} : "\"-Xms" +  (task.memory.toGiga()/10 )+"g "+ "-Xmx" + (task.memory.toGiga()-8)+ "g\""

	"""	
	#Quality and adapter trim:
	bbduk.sh ${markdup_java_options} in=${pairId}_dedupe_R1.fq in2=${pairId}_dedupe_R2.fq out=${pairId}_trimmed_R1_tmp.fq \
	out2=${pairId}_trimmed_R2_tmp.fq outs=${pairId}_trimmed_singletons_tmp.fq ktrim=r \
	k=$params.kcontaminants tossjunk=t mink=$params.mink hdist=$params.hdist qtrim=rl trimq=$params.phred \
	minlength=$params.minlength ref=$adapters qin=$params.qin threads=${task.cpus} tbo tpe 
	
	#Synthetic contaminants trim:
	bbduk.sh ${markdup_java_options} in=${pairId}_trimmed_R1_tmp.fq in2=${pairId}_trimmed_R2_tmp.fq \
	out=${pairId}_trimmed_R1.fq tossjunk=t out2=${pairId}_trimmed_R2.fq k=31 ref=$phix174ill,$artifacts \
	qin=$params.qin threads=${task.cpus} 

	#Synthetic contaminants trim for singleton reads:
	bbduk.sh ${markdup_java_options} in=${pairId}_trimmed_singletons_tmp.fq out=${pairId}_trimmed_singletons.fq \
	k=31 ref=$phix174ill,$artifacts tossjunk=t qin=$params.qin threads=${task.cpus}

	#Removes tmp files. This avoids adding them to the output channels
	rm -rf ${pairId}_trimmed*_tmp.fq 

	"""
}


/*
 *
 * Step 4: FastQC post-filter and -trim (run per sample)
 *
 */

process runFastQC_postfilterandtrim {
    cache 'deep'
    tag { "rFQC_post_FT.${pairId}" }

    publishDir "${params.outdir}/FastQC_post_filter_trim", mode: "copy"

    input:
    	set val(pairId), file("${pairId}_trimmed_R1.fq"), file("${pairId}_trimmed_R2.fq") from filteredReadsforQC

    output:
        file("${pairId}_fastqc_postfiltertrim/*.zip") into fastqc_files_2

    """
    mkdir ${pairId}_fastqc_postfiltertrim
    fastqc --outdir ${pairId}_fastqc_postfiltertrim \
    ${pairId}_trimmed_R1.fq \
    ${pairId}_trimmed_R2.fq
    """
}

process runMultiQC_postfilterandtrim {
	cache 'deep'
    tag { "rMQC_post_FT" }

    publishDir "${params.outdir}/FastQC_post_filter_trim", mode: 'copy'

    input:
        file('*') from fastqc_files_2.collect()

    output:
        file('multiqc_report.html')

    """
    multiqc .
    """
}

/*
 *
 * Step 5: Decontamination (run per sample)
 *
 */

process decontaminate {
	cache 'deep'
	tag{ "decon.${pairId}" }

	publishDir  "${params.outdir}/decontaminate" , mode: 'copy', pattern: "*_clean.fq.gz"

	input:
	set val(pairId), file("${pairId}_trimmed_R1.fq"), file("${pairId}_trimmed_R2.fq"), file("${pairId}_trimmed_singletons.fq") from todecontaminate
	file refForeignGenome from refForeignGenome_ref
	
	output:
	file "*_clean.fq.gz"
	set val(pairId), file("${pairId}_clean.fq") into cleanreadstometaphlan2, cleanreadstohumann2 
	set val(pairId), file("${pairId}_cont.fq") into topublishdecontaminate
	
	script:
	markdup_java_options = (task.memory.toGiga() < 8) ? ${params.markdup_java_options} : "\"-Xms" +  (task.memory.toGiga()/10 )+"g "+ "-Xmx" + (task.memory.toGiga()-8)+ "g\""

	"""
	
	#Decontaminate from foreign genomes
	bbwrap.sh  ${markdup_java_options} mapper=bbmap append=t in1=${pairId}_trimmed_R1.fq,${pairId}_trimmed_singletons.fq in2=${pairId}_trimmed_R2.fq,null \
	outu=${pairId}_clean.fq outm=${pairId}_cont.fq minid=$params.mind \
	maxindel=$params.maxindel bwr=$params.bwr bw=12 minhits=2 qtrim=rl trimq=$params.phred \
	path=$refForeignGenome qin=$params.qin threads=${task.cpus} untrim quickmatch fast
	
	gzip -c ${pairId}_clean.fq > ${pairId}_clean.fq.gz

	"""
}


/*
 *
 * Step 6:  metaphlan2 (run per sample)
 *
 */

process metaphlan2 {
	cache 'deep'
	tag{ "metaphlan2.${pairId}" }

	publishDir  "${params.outdir}/metaphlan2", mode: 'copy', pattern: "*.tsv"

	input:
	set val(pairId), file(infile) from cleanreadstometaphlan2
	//because mpa_pkl is used for metaphlan2 and strainphlan processes it needs to be defined with a channel and referenced here with .collect() otherwise it will only run one samples
	file mpa_pkl from mpa_pkl_m.collect()  
	file bowtie2db from bowtie2db_ref

    	output:
	file "${pairId}_metaphlan_profile.tsv" into metaphlantohumann2, metaphlantomerge
	file "${pairId}_bt2out.txt" into topublishprofiletaxa
	file "${pairId}_sam.bz2" into strainphlan


	script:
	"""
	#If a file with the same name is already present, Metaphlan2 will crash
	rm -rf ${pairId}_bt2out.txt

	#Estimate taxon abundances
	metaphlan2.py --input_type fastq --tmp_dir=. --biom ${pairId}.biom --bowtie2out=${pairId}_bt2out.txt \
	--samout ${pairId}_sam.bz2 \
	--mpa_pkl $mpa_pkl  --bowtie2db $bowtie2db/ --bt2_ps $params.bt2options --nproc ${task.cpus} \
	$infile ${pairId}_metaphlan_profile.tsv


	"""
}

/*
 *
 * Step 7:  merge all metaphlan2 per sample outputs into single abundance table
 *
 */

process merge_metaphlan2 {
	cache 'deep'
	tag{ "merge_metaphlan2_table" }
	
	publishDir  "${params.outdir}/metaphlan2", mode: 'copy'
	
	input: file('*') from metaphlantomerge.collect()
	
	output: file "metaphlan_merged_abundance_table.tsv"
	
	script:
	"""

 	merge_metaphlan_tables.py *_metaphlan_profile.tsv > metaphlan_merged_abundance_table.tsv
	
	"""
	
	
}

/*
 *
 * Step 8:  Create functional profiles with humann2 (run per sample)
 *
 */	

process humann2 {
	cache 'deep'
	tag{ "humann2.${pairId}" }

	publishDir  "${params.outdir}/humann2", mode: 'copy', pattern: "*.{tsv,log}"
	
	
	input:
	set val(pairId), file(cleanreads) from cleanreadstohumann2
	file(humann2_profile) from metaphlantohumann2
	file chocophlan from chocophlan_ref
	file uniref from uniref_ref
	
    	output:
	file "${pairId}_genefamilies.tsv"
	file "${pairId}_pathcoverage.tsv"
	file "${pairId}_pathabundance.tsv"
	
	//Those may or may not be kept, according to the value of the keepCCtmpfile parameter
	set ("${pairId}_bowtie2_aligned.sam", "${pairId}_bowtie2_aligned.tsv", "${pairId}_diamond_aligned.tsv", 
	     "${pairId}_bowtie2_unaligned.fa", "${pairId}_diamond_unaligned.fa") into topublishhumann2	

	script:
	"""
	#Functional annotation
	humann2 --input $cleanreads --output . --output-basename ${pairId} \
	--taxonomic-profile $humann2_profile --nucleotide-database $chocophlan --protein-database $uniref \
	--pathways metacyc --threads ${task.cpus} --memory-use maximum

	
	#Performs functional annotation, redirect is done here because HUMAnN2 freaks out


	#Some of temporary files (if they exist) may be moved in the working directory, 
	#according to the keepCCtmpfile parameter. Others (such as the bowties2 indexes), 
	#are always removed. Those that should be moved, but have not been created by 
	#HUMAnN2, are now created by the script (they are needed as output for the channel)
	files=(${pairId}_bowtie2_aligned.sam ${pairId}_bowtie2_aligned.tsv ${pairId}_diamond_aligned.tsv \
	${pairId}_bowtie2_unaligned.fa ${pairId}_diamond_unaligned.fa)
	
	for i in {1..5}
	do
		if [ -f ${pairId}_humann2_temp/\${files[((\$i-1))]} ]
		then
			mv ${pairId}_humann2_temp/\${files[((\$i-1))]} .
		else
			touch \${files[((\$i-1))]}
		fi
	done
	rm -rf ${pairId}_humann2_temp/

 	"""
}

/*
 *
 * Step 9: Strainphlan: sample2markers
 *
 */

process strainphlan_1 {
	cache 'deep'
	tag{ "strainphlan_1" }
	
	publishDir  "${params.outdir}/strainphlan", mode: 'copy', pattern: "*.markers"
			
	input: 
	file('*') from strainphlan.collect()
	
	output: 
	file "*.markers" into sample_markers
	
	script:
	"""
	sample2markers.py --ifn_samples *sam.bz2 --input_type sam --output_dir . --nprocs ${task.cpus} &> log.txt

	"""
	
	
}
/*
 *
 * Step 10:  Strainphlan strain-specific tree
 *
 */

process strainphlan_2 {
	cache 'deep'
	tag{ "strainphlan_2" }
	
	publishDir  "${params.outdir}/strainphlan", mode: 'copy'
		
	when:
  	params.strain_of_interest
	
	input: 
	file ("*") from sample_markers.collect()
	file mpa_pkl from mpa_pkl_s.collect()
	file metaphlan_markers from MM
	
	output: 
	file "*"
	
	script:
	"""
	strainphlan.py --mpa_pkl $mpa_pkl --ifn_samples *.markers --output_dir . --print_clades_only > clades.txt

	extract_markers.py --mpa_pkl $mpa_pkl --ifn_markers $metaphlan_markers \
	--clade $params.strain_of_interest --ofn_markers "${params.strain_of_interest}.markers.fasta"
		
	strainphlan.py --mpa_pkl $mpa_pkl --ifn_samples *.markers --ifn_markers "${params.strain_of_interest}.markers.fasta" --ifn_ref_genomes $params.strain_reference_genome \
        --output_dir . --clades $params.strain_of_interest

	"""
	
	
}
/*
 *
 * Step 11:  Save tmp files from metaphlan2 and humann2 if requested
 *
 */	
	
process saveCCtmpfile {
	cache 'deep'
	tag{ "saveCCtmpfile" }
	publishDir  "${params.outdir}/CCtmpfiles", mode: 'copy'
		
	input:
	file (tmpfile) from topublishprofiletaxa.mix(topublishhumann2).flatMap()

	output:
	file "$tmpfile"

	when:
	params.keepCCtmpfile
		
	script:
	"""
	echo $tmpfile
	"""
}

/*
 *
 * Step 11: Completion e-mail notification
 *
 */
workflow.onComplete {
  
    def subject = "[uct-yamp] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[uct-yamp] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = params.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if(workflow.container) email_fields['summary']['Docker image'] = workflow.container

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir" ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[uct-yamp] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[uct-yamp] Sent summary e-mail to $params.email (mail)"
        }
    }
}
