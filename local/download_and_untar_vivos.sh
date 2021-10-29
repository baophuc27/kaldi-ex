remove_archive=true
dat$1
data_url=$2
set -e


if [ -z "$data_url" ]; then
    echo "$0: empty URL"
    exit 1;
fi

if [ -f data/vivos.tar.gz ]; then
    echo "$data/vivos.tar.gz exists"
fi

if [ ! -f data/vivos.tar.gz ]; then
    echo "$0L downloading VIVOS data from $data_url"

    cd data
    if ! wget --no-check-certificate $data_url; then
        echo "$0: error executing wget for $data_url"
        remove_archive=false
        exit 1;
    fi
fi


if ! tar -xvzf data/vivos.tar.gz -C data; then
    echo "$0: error when untar vivos.tar.gz"
    remove_archive=false
    exit 1;
fi


# Rename directory to audio for easier readability
# if [ ! -d vivos ]; then
#     mv vivos audio
# fi

echo "$0: Successfully downloaded and untar vivos.data.gz "


if $remove_archive; then
    echo "$0: removing data/vivos.tar.gz"
    rm -rf data/vivos.data.gz
fi
