FROM ubuntu:latest

MAINTAINER pierre.zemb.isen@gmail.com

RUN apt update && apt upgrade && apt install wget openssh-server vim qemu qemu-kvm unzip virtinst

RUN wget https://releases.hashicorp.com/packer/0.9.0/packer_0.9.0_linux_amd64.zip -O /packer_0.9.0_linux_amd64.zip
RUN unzip /packer_0.9.0_linux_amd64.zip
