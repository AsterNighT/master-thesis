compile: 
    latexmk -xelatex -outdir=out zjuthesis

count: compile
    bash script/utils/word_count.sh