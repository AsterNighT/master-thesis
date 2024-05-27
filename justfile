compile: 
    latexmk -xelatex -f -outdir=out zjuthesis

clean:
    latexmk -C

count: compile
    bash script/utils/word_count.sh