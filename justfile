compile: clean
    latexmk -xelatex -f -outdir=out zjuthesis

clean:
    latexmk -C

count:
    bash script/utils/word_diff.sh