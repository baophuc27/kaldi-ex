# -----------------------------------------------------------------
# THIS SCRIPT PREPARE TRAINING FILES FROM THE RAW DATASET

# text: transcription of the corpus. 
# FORMAT: uttd_id WORD1 WORD2 WORD3 

# wav.scp: contains location of the audio file. 
# FORMAT: utt_id path/file 

# spk2gender: contains the mapping of each speaker to its corresponding gender
# FORMAT: speaker_id m|f  

# utt2spk: mapping of each utterance to its corresponding speaker
# FORMAT: utt_id speaker_id 

# corpus.txt: contains all of the transcriptions

import os
import numpy as np 
import argparse



class VivosDataProcessor:
    def __init__(self,raw_dir,processed_dir):
        """ Wrapper for Vivos data processor

        Arguments:
            raw_dir (path): directory to processed vivos data

            processed_dir (path): directory to processed vivos data.
            Each folder contains text,wav.scp,utt2spk, spk2gender
        """
        self.raw_dir = raw_dir
        self.processed_dir = processed_dir


        print("=========== Init Vivos project ===========")
        self._init_proj_structure()
        self._copy_sound_files()
        self._make_text()
        self._make_wav()
        self._make_utt2spk()
        self._make_spk2gender()
        
    # ================================
    # ==== INIT PROJECT STRUCTURE ====
    # ================================
    def _init_proj_structure(self):

        os.system("mkdir -p audio")
        os.system("mkdir -p audio/train")
        os.system("mkdir -p audio/test")

        os.system("mkdir -p data/train")
        os.system("mkdir -p data/test")
        os.system("mkdir -p data/local")
        os.system("mkdir -p data/local/dict")        
    

    # ==================================
    # === COPY AND RE-STRUCTURE AUDIO ==
    # ==================================
    def _copy_sound_files(self):
        """
        Copy audio waves from raw vivos dataset to another
        directory for an easier readability. (./audio)
        """
        for dir_type in ["train","test"]:
            wav_dir = "data/vivos/{}/waves".format(dir_type)
            dest_dir = "audio/{}".format(dir_type)

            for speaker in os.listdir(wav_dir):
                original_file = os.path.join(wav_dir,speaker)
                os.system("cp -r {} {}".format(original_file,dest_dir))

                # Truncate filename
                for filename in os.listdir(os.path.join(dest_dir,speaker)):
                    items = filename.split(".")
                    _, utt_id = items[0].split("_")
                    spk_dir = os.path.join(dest_dir,speaker) #audio/train/VIVOSSPK04
                    os.system("mv {0}/{1} {0}/{2}.wav".format(spk_dir,filename,utt_id))


    def _make_text(self):
        """
        Build text file for vivos data, which contains utterance id 
        and its transcript.
        """
        def _make_sub_text(sub_dir):
            raw_path = os.path.join(self.raw_dir,sub_dir)
            processed_path = os.path.join(self.processed_dir,sub_dir)

            transcript = open(os.path.join(raw_path,"prompts.txt")).read()
            lines = transcript.splitlines()

            output = []
            for line in lines:
                items = line.split()
                utt_id = items[0].replace("_","-")
                text = " ".join(items[1:]).lower()
                line_content = "{} {}".format(utt_id,text)
                output.append(line_content)

            text = "\n".join(output)
            open(os.path.join(processed_path,"text"),"w").write(text)

        _make_sub_text("test")
        _make_sub_text("train")


    def _make_wav(self):
        """
        Create wav.scp files, which contains utt_id and its
        corresponding audio reference.
        """
        def _make_sub_wav(sub_dir):
            raw_path = os.path.join(self.raw_dir,sub_dir)
            processed_path = os.path.join(self.processed_dir,sub_dir)

            transcript = open(os.path.join(raw_path,"prompts.txt")).read()
            lines = transcript.splitlines()

            output = []
            for line in lines:
                items = line.split()
                speaker_id,utt_id = items[0].split("_")
                wav = "{0}-{1} ./audio/{2}/{0}/{1}.wav".format(speaker_id,utt_id,sub_dir)
                output.append(wav)
            
            # Due to kaldi's requirement
            output = sorted(output, key=lambda x: x.split()[0])
            content = "\n".join(output) + "\n"
            outfile = "data/{}/wav.scp".format(sub_dir)
            open(outfile,"w").write(content)

        _make_sub_wav("test")
        _make_sub_wav("train")
    
    def _make_spk2gender(self):
        for dir_type in ["train","test"]:
            original_file = os.path.join(self.raw_dir,dir_type,"genders.txt")
            dest_file = os.path.join(self.processed_dir,dir_type,"spk2gender")
            
            content = open(original_file).read()
            open(dest_file,"w").write(content)
        
    
    def _make_utt2spk(self):
        """
        Build utt2spk file, which map the utterance to its speaker id
        """
        def _make_sub_utt2spk(sub_dir):
            raw_path = os.path.join(self.raw_dir,sub_dir)
            processed_path = os.path.join(self.processed_dir,sub_dir)

            transcript = open(os.path.join(raw_path,"prompts.txt")).read()
            lines = transcript.splitlines()

            output = []
            for line in lines:
                items = line.split()
                speaker_id,utt_id = items[0].split("_")
                utt_map = "{0}-{1} {0}".format(speaker_id,utt_id)
                output.append(utt_map)
            
            # Due to kaldi's requirement
            output = sorted(output, key=lambda x: x.split()[0])
            content = "\n".join(output) + "\n"
            outfile = "data/{}/utt2spk".format(sub_dir)
            open(outfile,"w").write(content)
        
        _make_sub_utt2spk("test")
        _make_sub_utt2spk("train")
        

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Prepare VIVOS dataset"
    )

    parser.add_argument('--raw-dir', help="Path to raw VIVOS data directory",required=True)
    parser.add_argument('--processed-dir', help="Path to destination VIVOS data directory", required=True)

    args = parser.parse_args()
    VivosDataProcessor(**vars(args))
