Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"
    vb.cpus = "4"
  end
  config.vm.provision "shell", inline: "apt-get -y update"
  config.vm.provision "shell", inline: "apt-get -y install apt-transport-https ca-certificates"
  config.vm.provision "shell", inline: "apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D"
  config.vm.provision "shell", inline: "echo deb\ https://apt.dockerproject.org/repo\ ubuntu-trusty\ main >/etc/apt/sources.list.d/docker.list"
  config.vm.provision "shell", inline: "apt-get -y update"
  config.vm.provision "shell", inline: "apt-get -y purge lxc-docker"
  config.vm.provision "shell", inline: "apt-get -y install linux-image-extra-$(uname -r) linux-image-extra-virtual"
  config.vm.provision "shell", inline: "apt-get -y install docker-engine"
  config.vm.provision "shell", inline: "usermod -aG docker vagrant"
end
