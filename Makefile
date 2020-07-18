.PHONY: setup train n nb

jupyter:
	PYTHONPATH=`pwd` screen .venv/bin/jupyter notebook --ip 0.0.0.0 --port=8881 --no-browser .

browser:
	PYTHONPATH=`pwd` screen .venv/bin/jupyter notebook --ip 0.0.0.0 --port=8881 .

# GPU id, -1 = train on CPU
GPU:=0
CUDA:=91
CW:=150
WF:=-b data/models/navec_hudlit.model
OPTS:=
EPOCHS:=30
N:=ru2_syntagrus_${CW}
S:=.venv/bin/python -u -m spacy
D:=data/syntagrus
G:=data/grameval
Gdev:=$G/GramEval2020-master/dataOpenTest
Gtrain:=$G/GramEval2020-master/dataTrain
F:=$(shell date +"%m-%d-%y_%H-%M-%S")
M:=data/models/${N}-${F}
T:=.venv/bin/python -u -m training.spacy_train

setup:
	test -d .venv || python3 -m venv .venv
	poetry install

setup_cuda: setup
	./cuda.sh cuda${CUDA}
	.venv/bin/python3 -c "import spacy;spacy.require_gpu()"

$G/GramEval2020-master:
	mkdir -p $G
	curl -L https://github.com/dialogue-evaluation/GramEval2020/archive/master.zip -o $G/master.zip
	#cp data/master.zip $G/master.zip
	cd $G; unzip master.zip

$G/poetry-dev.conllu: $G/GramEval2020-master
	cat ${Gdev}/GramEval2020-RuEval2017-Lenta-news-dev.conllu >$G/news-dev.conllu
	cat ${Gdev}/GramEval2020-GSD-wiki-dev.conllu >$G/wiki-dev.conllu
	cat ${Gdev}/GramEval2020-SynTagRus-dev.conllu >$G/fiction-dev.conllu
	cat ${Gdev}/GramEval2020-RuEval2017-social-dev.conllu >$G/social-dev.conllu
	cat ${Gdev}/GramEval2020-Taiga-poetry-dev.conllu >$G/poetry-dev.conllu

$G/poetry.conllu: $G/GramEval2020-master
	cat ${Gdev}/GramEval2020-RuEval2017-Lenta-news-dev.conllu ${Gtrain}/MorphoRuEval2017-Lenta-train.conllu >$G/news.conllu
	cat ${Gdev}/GramEval2020-GSD-wiki-dev.conllu ${Gtrain}/GramEval2020-GSD-train.conllu >$G/wiki.conllu
	cat ${Gdev}/GramEval2020-SynTagRus-dev.conllu ${Gtrain}/GramEval2020-SynTagRus-train-v2.conllu ${Gtrain}/MorphoRuEval2017-JZ-gold.conllu >$G/fiction.conllu
	cat ${Gdev}/GramEval2020-RuEval2017-social-dev.conllu ${Gtrain}/GramEval2020-Taiga-social-train.conllu ${Gtrain}/MorphoRuEval2017-VK-gold.conllu >$G/social.conllu
	cat ${Gdev}/GramEval2020-Taiga-poetry-dev.conllu ${Gtrain}/GramEval2020-Taiga-poetry-train.conllu >$G/poetry.conllu

$G/poetry-dev.json: $G/poetry-dev.conllu
	./convert.sh 1 $G/news-dev.conllu $G/news-dev.json
	./convert.sh 1 $G/wiki-dev.conllu $G/wiki-dev.json
	./convert.sh 1 $G/fiction-dev.conllu $G/fiction-dev.json
	./convert.sh 1 $G/social-dev.conllu $G/social-dev.json
	./convert.sh 1 $G/poetry-dev.conllu $G/poetry-dev.json

$G/poetry.json: $G/poetry.conllu
	./convert.sh 1 $G/news.conllu $G/news.json
	./convert.sh 1 $G/wiki.conllu $G/wiki.json
	./convert.sh 1 $G/fiction.conllu $G/fiction.json
	./convert.sh 1 $G/social.conllu $G/social.json
	./convert.sh 1 $G/poetry.conllu $G/poetry.json

$N/quality.txt: $G/poetry.json $G/poetry-dev.json
	echo "" > $@
	./eval.sh $N $G/news-dev.json >> $@
	./eval.sh $N $G/wiki-dev.json >> $@
	./eval.sh $N $G/fiction-dev.json >> $@
	./eval.sh $N $G/social-dev.json >> $@
	./eval.sh $N $G/poetry-dev.json >> $@
	./eval.sh $N $G/news.json >> $@
	./eval.sh $N $G/wiki.json >> $@
	./eval.sh $N $G/fiction.json >> $@
	./eval.sh $N $G/social.json >> $@
	./eval.sh $N $G/poetry.json >> $@

eval: $N/quality.txt
	cat $N/quality.txt

$D:
	git clone https://github.com/UniversalDependencies/UD_Russian-SynTagRus.git $D

$D/train.json: $D
	./convert.sh 10 $D/ru_syntagrus-ud-train.conllu $D/train.json

$D/test.json: $D
	./convert.sh 1 $D/ru_syntagrus-ud-test.conllu $D/test.json

$D/dev.json: $D
	./convert.sh 1 $D/ru_syntagrus-ud-dev.conllu $D/dev.json

data/navec/navec_hudlit_v1_12B_500K_300d_100q.tar:
	curl https://storage.yandexcloud.net/natasha-navec/packs/navec_hudlit_v1_12B_500K_300d_100q.tar -o data/navec/navec_hudlit_v1_12B_500K_300d_100q.tar

data/models/navec_hudlit.model: data/navec/navec_hudlit_v1_12B_500K_300d_100q.tar
	.venv/bin/python -m training.navec2spacy -m data/navec/navec_hudlit_v1_12B_500K_300d_100q.tar -o data/models/navec_hudlit.model

$N/accuracy.txt: $D/train.json $D/test.json data/models/navec_hudlit.model
	mkdir -p $M
	OPENBLAS_NUM_THREADS=1 $T -p tagger,parser -R -g ${GPU} -cw ${CW} ${WF} ${OPTS} -G -n ${EPOCHS} ru $M $D/train.json $D/test.json | tee $M/accuracy.txt
	mkdir -p $N
	cp -r $M/model-final/* $N
	cp $M/accuracy.txt $@

train: $N/accuracy.txt

train-check: $D/dev.json $D/test.json 
	OPENBLAS_NUM_THREADS=1 $T -g ${GPU} -G -n 2 ru $M $D/dev.json $D/test.json
	mkdir -p ru2_train_on_dev/
	cp -r $M/model-final/* ru2_train_on_dev/

train-ner: 
	echo $T -g ${GPU} -G -n 20 ru $M $D/ru_syntagrus-ud-train.json $D/ru_syntagrus-ud-test.json
	#mkdir -p $N/
	#cp -r $M/model-final/* $N/
