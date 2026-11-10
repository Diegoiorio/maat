#!/bin/bash
# setup-env.sh <copy> <deps dir> -- prepares the environment of a copy of tox, with the network open.
# Wheels only, exact versions and hashes, downloaded once into <deps dir>/wheels. After it the suite runs offline.
# The copy has no git history, so the version that hatch-vcs would read from the tags is given explicitly: the last
# release before the starting commit (the suite's own configuration examples ask for tox >= 4.x).
set -eu
copy=$(cd "$1" && pwd)
mkdir -p "$2"
deps=$(cd "$2" && pwd)
TOX_VERSION=4.64.5
mkdir -p "$deps/wheels"
cat > "$deps/requirements-lock.txt" <<'LOCK'
anyio==4.16.0 --hash=sha256:c66ae634e0b8228396b801741beb3294326d4b6102f7bba4041c0dfb58c29026
argcomplete==3.7.2 --hash=sha256:6029205678bdd9c1c728a155f5f9ecf5812393f969eef58807641a2bc2aa5b19
argon2-cffi==25.1.0 --hash=sha256:fdc8b074db390fccb6eb4a3604ae7231f219aa669a2652e0f20e16ba513d5741
argon2-cffi-bindings==26.1.0 --hash=sha256:27f1821903e2ceadcb88ec2b45ef190897b7682449c772f4d9b53e42c520cf29
attrs==26.1.0 --hash=sha256:c647aa4a12dfbad9333ca4e71fe62ddc36f4e63b2d260a37a8b83d2f043ac309
build==1.6.1 --hash=sha256:ecd351a4be9d35a9eaaba244a7687143c9c7d4aea6ac964e7e7ddab20cbcf4e7
cachetools==8.0.0 --hash=sha256:5af562e5078f0086771a1e3832a9c3dbf5d336b6e2794a2c12a64680a4c9087d
certifi==2026.10.23 --hash=sha256:e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1
cffi==2.1.1 --hash=sha256:c1453022f490d2459a11819d83ad1d586e9ff65a12ac3e705ffebd46d3685dcf
chardet==7.7.0 --hash=sha256:feb66c96264e3e6a9ff0c7318ce0028800b6c18ad07c8000d2404a108d1ef767
charset-normalizer==3.5.2 --hash=sha256:3d31298449090ab8d47b7b1b2a555ff73cac7ed438a08b7ac160980c7ebed649
check-manifest==0.51 --hash=sha256:f5f35ed561012fc2115bb070e42a748ac2e034cf8904ab4dfaae893859085ca4
colorama==0.4.6 --hash=sha256:4f1d9991f5acc0ca119f9d443620b77f9d6b33703e51011c16baf57afb285fc6
covdefaults==2.3.0 --hash=sha256:2832961f6ffcfe4b57c338bc3418a3526f495c26fb9c54565409c5532f7c41be
coverage==7.17.2 --hash=sha256:36314997533266bde3d07765289674304d61bfe49165bb1b4fa9be12cb4ba0d1
defusedxml==0.7.1 --hash=sha256:a352e7e428770286cc899e2542b6cdaedb2b4953ff269a210103ec58f6198a61
detect-test-pollution==1.2.0 --hash=sha256:96095425dadf95d4ceabd585659ccc3197e88dfb1efb02a8479b27d8ad1a3afb
devpi-client==7.3.0 --hash=sha256:fa51a27eb0f98415426dc3d2488006345701441f8e7ad5d170b5c674c2910492
devpi-common==4.1.2 --hash=sha256:73d639065930505227fd003dd525a27cfcf5044e7d48d25ba4873b6e3e659987
devpi-process==1.3.3 --hash=sha256:6ffedb0931d6cfa0a45e08bd5e06d5371c0e5c2733e2db6a2e5bbd6018fa2ab9
devpi-server==6.21.0 --hash=sha256:7facdfb0e900c1a8e3c2240c46c92dd14af110b8b55bd334aa6888d4508e5de4
diff_cover==11.0.1 --hash=sha256:40d559e47ee9bcec35194fd9726d408a242608c54fbd0cdab244ae4324c1c7da
distlib==0.4.4 --hash=sha256:cf09d55b1e85a89576b036aeb71550bfd68320f3f21761ca329eadadad918638
docutils==0.23 --hash=sha256:25d013af9bf23bc1c7b2b093dff4208166c53a94786c9e447808335ef1185fea
execnet==2.1.2 --hash=sha256:67fba928dd5a544b783f6056f449e5e3931a5c378b128bc18501f7ea79e296ec
filelock==4.2.9 --hash=sha256:a379c50a729e5b68c8519a4d26489f755d9769960a236ecd838190e2a78db2e9
flaky==3.8.1 --hash=sha256:194ccf4f0d3a22b2de7130f4b62e45e977ac1b5ccad74d4d48f3005dcc38815e
h11==0.16.0 --hash=sha256:63cf8bbe7522de3bf65932fda1d9c2772064ffb3dae62d55932da54b31cb6c86
hatch-vcs==0.5.0 --hash=sha256:b49677dbdc597460cc22d01b27ab3696f5e16a21ecf2700fb01bc28e1f2a04a7
hatchling==1.33.0 --hash=sha256:415290b84f464d2884303fca8974d38e7b85579069fab02a15db0828fbb1446d
httpcore==1.0.9 --hash=sha256:2d400746a40668fc9dec9810239072b40b4484b640a8c38fd654a024c7a1bf55
httpx==0.28.1 --hash=sha256:d909fcccc110f8c7faf814ca82a9a4d816bc5a6dbfea25d6591d6985b8ba59ad
hupper==1.12.1 --hash=sha256:e872b959f09d90be5fb615bd2e62de89a0b57efc037bdf9637fb09cdf8552b19
idna==3.20 --hash=sha256:ab7ae7122974553370f0bdb919e1a960b2cd1bc1ef0276416d896db81c14582c
iniconfig==2.3.1 --hash=sha256:9121e2c1fdb355232495be3194c8dfe87ccc2d5dee45947b78e68f499790d7a7
itsdangerous==2.2.0 --hash=sha256:c6242fc49e35958c8b15141343aa660db5fc54d4f13a1db01a3f5891b98700ef
Jinja2==3.1.6 --hash=sha256:85ece4451f492d0c13c5dd7c13a64681a86afae63a5f347908daf103ce6d2f67
lazy==2.0 --hash=sha256:6bf06f6a71dbe6148f3948c6388b264772493972ad22fb958d24bb52e7e7ec9b
MarkupSafe==3.0.4 --hash=sha256:8e124f974786f831d6043728e38296969d3579db8896fe004682f5758e613581
packaging==26.3 --hash=sha256:d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c
packaging-legacy==23.0.post0 --hash=sha256:6cd21cd283c09409349bccc10bb55bfd837b4aab86a7b0f87bfcb8dd9831a8a3
passlib==1.7.4 --hash=sha256:aa6bca462b8d8bda89c70b382f0c298a20b5560af6cbfa2dce410c0a2fb669f1
PasteDeploy==3.1.0 --hash=sha256:76388ad53a661448d436df28c798063108f70e994ddc749540d733cdbd1b38cf
pathspec==1.1.1 --hash=sha256:a00ce642f577bf7f473932318056212bc4f8bfdf53128c78bbd5af0b9b20b189
pdm-backend==2.5.0 --hash=sha256:5b8746b567a16a1fd506ce66ee28e89d46374526f52238aa1b96cc2c08245c63
pkginfo==2.0 --hash=sha256:98c7aaa804dfe017b0de65d4b41a2f4649a656f43d3c21525b13e8075716fa1b
plaster==1.1.2 --hash=sha256:42992ab1f4865f1278e2ad740e8ad145683bb4022e03534265528f0c23c0df2d
plaster-pastedeploy==1.0.1 --hash=sha256:ad3550cc744648969ed3b810f33c9344f515ee8d8a8cec18e8f2c4a643c2181f
platformdirs==4.14.5 --hash=sha256:8e778c6fa421516f4d3369449f8df3b0e1b72c0e0005fe88e3ec772d0a14e750
pluggy==1.7.0 --hash=sha256:7dd7b0d8832ba3cb632c306926ded123429211b83641b35dc5c41ad2d34f9bec
psutil==7.2.2 --hash=sha256:076a2d2f923fd4821644f5ba89f059523da90dc9014e85f8e45a5774ca5bc6f9
py==1.11.0 --hash=sha256:607c53218732647dff4acdfcd50cb62615cedf612e72d1724fb1a0cc6405b378
pycparser==3.12 --hash=sha256:a076f3f489b39b43ed13563a1dafe42447445bec2e294154ec5c57fcdda4c85e
Pygments==2.21.0 --hash=sha256:2363c69b61c4a97c838da3b130dcd6468f4848992b21a82f2a63ec34377137d9
pyproject-api==1.12.5 --hash=sha256:d9cc8c913912035ecd95451a97216083c738b5ff31c45fd168c1f3a28baf01d7
pyproject_hooks==1.3.3 --hash=sha256:5fc53fdac9f7bd63fbcdc868fb5f90b4784d78a53a3d3388cd738b807441a20b
pyramid==2.1 --hash=sha256:0aa62604221f6a8ac6e77a0faa02a5b7a294d6675f15581d8d416dffe2ac98e7
pytest==9.2.0 --hash=sha256:07acdcf88ec174f907dc01af70bf52d49b014bbab03faeeade31c96b18c2e588
pytest-cov==7.1.0 --hash=sha256:a0461110b7865f9a271aa1b51e516c9a95de9d696734a2f71e3e78f46e1d4678
pytest-mock==3.17.0 --hash=sha256:1b82aa4b37137248bd687055e109723debeb07b489de1565297dc9589c5f2d6b
pytest-timeout==2.4.0 --hash=sha256:c42667e5cdadb151aeb5b26d114aff6bdf5a907f176a007a30b940d3d865b5c2
pytest-xdist==3.8.0 --hash=sha256:202ca578cfeb7370784a8c33d6d05bc6e13b4f25b5053c30a152269fd10f0b88
python-dateutil==4.0.0 --hash=sha256:a5e246f79eb80475e691bf93862cead98decd8a498cf53ba0516fcdc0f50dc1c
python-discovery==1.9.5 --hash=sha256:a1fae8fca11e4bc61e38491c2aafff29e430b3c5e272d51ae52fb895bc4c0fac
re-assert==1.1.0 --hash=sha256:6b2902d5beac2a0e715eb0312fcb226ab4da21d1ea6953441734734b5b68cd48
regex==2026.11.9 --hash=sha256:ab4a0c5cd3df4b93841ba4a419a5438b2a4c78a4e418682fc674e3f50d56b857
repoze-lru==0.8 --hash=sha256:979a30d2e567e31f292009ba4467aa444c89ee0da3e3013980c35f1fb4f19d99
requests==2.34.2 --hash=sha256:2a0d60c172f83ac6ab31e4554906c0f3b3588d37b5cb939b1c061f4907e278e0
ruamel.yaml==0.19.1 --hash=sha256:27592957fedf6e0b62f281e96effd28043345e0e66001f97683aa9a40c667c93
setuptools==81.0.0 --hash=sha256:fdd925d5c5d9f62e4b74b30d6dd7828ce236fd6ed998a08d81de62ce5a6310d6
setuptools-scm==10.3.4 --hash=sha256:82f34c3e3084fc2b57d397200637cc13f2338004052d2fee47baa5f0e902464e
strictyaml==1.7.3 --hash=sha256:fb5c8a4edb43bebb765959e420f9b3978d7f1af88c80606c03fb420888f5d1c7
time-machine==3.6.0 --hash=sha256:8116e2a534c84743cf7125acb1602d7e5ed30f1a3121538d31320e755f819c8a
tombi==1.11.1 --hash=sha256:a7aee7941ace5d6eb9105f41f2e909000d3306361fed5a5a079079b95dde86f0
tomli_w==1.2.0 --hash=sha256:188306098d013b691fcadc011abd66727d3c414c571bb01b1a174ba8c983cf90
tomlkit==0.15.2 --hash=sha256:05562412163a3037b94497385fb7f9204c637bc605af7a48199e41cf2272f437
translationstring==1.4 --hash=sha256:5f4dc4d939573db851c8d840551e1a0fb27b946afe3b95aafc22577eed2d6262
trove-classifiers==2026.9.21.13 --hash=sha256:8b1ff4f9c191b1040b71c37f1e445ab99732911e3cd91de52838453a854d7a17
typing_extensions==4.16.0 --hash=sha256:481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8
tzdata==2026.6 --hash=sha256:0a10eec6e13ef16b627fabed9a5f2ba61a62b1c67f327305f4e7e412a70b4aec
urllib3==2.8.0 --hash=sha256:0cf3cae568d36aa9576b28dfb35f11328f1cb974ca7647d9475ebb86c75ac6e3
vcs-versioning==2.6.0 --hash=sha256:f8bebd1302ebc12e67ceb30fc7dd698ec969414b6fa43b30c3f14ac9b1e72c41
venusian==3.1.1 --hash=sha256:0845808a985976acbceaa1fbb871c7fac4fb28ae75453232970e9c2c2866dbf4
virtualenv==21.15.6 --hash=sha256:4b99ab9b95ff11043939bb4cad2fa0449175fa5a478372864f62160cb6c1a7ed
waitress==3.0.2 --hash=sha256:c56d67fd6e87c2ee598b76abdd4e96cfad1f24cacdea5078d382b1f9d7b5ed2e
WebOb==1.8.11 --hash=sha256:4addd1d38d6a7fbe0eda22d45f25a40d74c8b290f3a99c0ac3d4023cf21f2da2
wheel==0.48.0 --hash=sha256:3217dcc807155e45db462d7ef2431f5ddda0d7273b700d05a67b271ceb1287ab
zope.deprecation==6.0 --hash=sha256:ff72d51c88b516b9ddf2cfb826381cc49f99a6a89b7d35c97faca7bee3b46da6
zope.interface==8.7 --hash=sha256:90aef6e0a9924af18f60528895f2fc50cb634191939d65b10a96d9ced05030b5
LOCK
python3 -m venv "$copy/.venv"
pip=("$copy/.venv/bin/python" -m pip --disable-pip-version-check)
if [ ! -f "$deps/wheels/.complete" ]; then
  "${pip[@]}" download -q --require-hashes --no-deps --only-binary :all: -d "$deps/wheels" -r "$deps/requirements-lock.txt"
  touch "$deps/wheels/.complete"
fi
"${pip[@]}" install -q --no-index --find-links "$deps/wheels" --require-hashes -r "$deps/requirements-lock.txt"
SETUPTOOLS_SCM_PRETEND_VERSION=$TOX_VERSION \
  "${pip[@]}" install -q --no-index --no-deps --no-build-isolation -e "$copy"
