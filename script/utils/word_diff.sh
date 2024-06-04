words=$(bash script/utils/word_count.sh | grep "Words in text" | tail -n 1 | awk '{print $NF}')
words=$(($words/2))
last_words=$(cat out/last_words.txt)

echo $words > out/last_words.txt

echo "Last time: $last_words words"
echo "Increased: $(($words-$last_words)) words"