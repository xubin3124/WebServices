#!/bin/bash
# asscan 获取 CF 反代节点

echo "本脚需要用root权限执行masscan扫描"
echo "请自行确认当前是否以root权限运行"
echo "当前脚本只支持linux amd64架构"
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update -f")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
n=0

for i in `echo ${linux_os[@]}`
do
	if [ $i == $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') ]
	then
		break
	else
		n=$[$n+1]
	fi
done

if [ $n == 5 ]
then
	echo "当前系统$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2)没有适配"
	echo "默认使用APT包管理器"
	n=0
fi

if [ -z $(type -P curl) ]
then
	echo "缺少curl,正在安装..."
	${linux_update[$n]}
	${linux_install[$n]} curl
fi
if [ -z $(type -P screen) ]
then
	echo "缺少screen,正在安装..."
	${linux_update[$n]}
	${linux_install[$n]} screen
fi
if [ -z $(type -P ldconfig) ]
then
	echo "缺少ldconfig,正在安装..."
	${linux_update[$n]}
	${linux_install[$n]} ldconfig
fi
if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') != "Alpine" ]
then
	if [ $(ldconfig -p | grep libpcap | wc -l) == 0 ]
	then
		echo "缺少libpcap,正在安装..."
		${linux_update[$n]}
		${linux_install[$n]} libpcap-dev
	fi
else
	if [ $(apk info -e libpcap | wc -l) == 0 ]
	then
		echo "缺少libpcap,正在安装..."
		${linux_update[$n]}
		${linux_install[$n]} libpcap-dev
	fi
fi

if [ $(cat /proc/net/dev | sed '1,2d' | awk -F: '{print $1}' | grep -w -v "lo" | sed -e 's/ //g' | wc -l) == 1 ]
then
	Interface=$(cat /proc/net/dev | sed '1,2d' | awk -F: '{print $1}' | grep -w -v "lo" | sed -e 's/ //g')
	echo "网口已经自动设置为 $Interface"
else
	if [ ! -f "setting.txt" ]
	then
		echo "多网口模式下,首次使用需要设置默认网口"
		echo "如需更改默认网口,请删除setting.txt后重新运行脚本"
		echo "当前可用网口如下"
		cat /proc/net/dev | sed '1,2d' | awk -F: '{print $1}' | grep -w -v "lo" | sed -e 's/ //g'
		read -p "选择当前需要抓包的网卡: " Interface
		if [ -z "$Interface" ]
		then
			echo "请输入正确的网口名称"
			exit
		fi
		if [ $(cat /proc/net/dev | sed '1,2d' | awk -F: '{print $1}' | grep -w -v "lo" | sed -e 's/ //g' | grep -w "$Interface" | wc -l) == 0 ]
		then
			echo "找不到网口 $Interface"
			exit
		else
			echo $Interface>setting.txt
		fi
	else
		Interface=$(cat setting.txt)
		echo "网口已经自动设置为 $Interface"
		echo "如需更改默认网口,请删除setting.txt后重新运行脚本"
	fi
fi

chmod +x masscan iptest
echo "本脚需要用root权限执行masscan扫描"
echo "请自行确认当前是否以root权限运行"
echo "1.单个AS模式"
echo "2.批量AS列表模式"
echo "3.清空缓存数据"
read -p "请输入模式号(默认模式1):" scanmode
if [ -z "$scanmode" ]
then
	scanmode=1
fi
if [ $scanmode == 1 ]
then
	clear
	echo "当前为单个AS模式"
	read -p "请输入AS号码(默认45102):" asn
	if [ -z "$asn" ]
	then
		asn=45102
	fi
	read -p "是否启用TLS[(默认1.是)0.否]:" tls
	if [ -z "$tls" ]
	then
		tls=1
	fi
	if [ $tls == 1 ]
	then
		read -p "请输入扫描端口(默认443):" port
		if [ -z "$port" ]
		then
			port=443
		fi
	else
		read -p "请输入扫描端口(默认80):" port
		if [ -z "$port" ]
		then
			port=80
		fi
	fi
elif [ $scanmode == 2 ]
then
	clear
	echo "当前批量AS列表模式"
	echo "待扫描的默认列表文件as.txt格式如下所示"
	echo -e "\n45102:443:1\n132203:443:1\n自治域号:端口号:TLS状态\n"
	read -p "请设置列表文件(默认as.txt):" filename
	if [ -z "$filename" ]
	then
		filename=as.txt
	fi
elif [ $scanmode == 3 ]
then
	rm -rf asn setting.txt ip.txt data.txt
	echo "所有缓存已清空!"
	exit
else
	echo "输入的数值不正确,脚本已退出!"
	exit
fi
read -p "请设置masscan pps rate(默认10000):" rate
read -p "请设置IP检测线程数(默认100):" max
read -p "是否需要测速[(默认0.否)1.是]:" mode
if [ -z "$mode" ]
then
	mode=0
fi
if [ $mode == 0 ]
then
	speedtest=0
else
	read -p "并发测速线程数(默认3):" speedtest
	if [ -z "$speedtest" ]
	then
		speedtest=3
	fi
fi
if [ -z "$rate" ]
then
	rate=10000
fi
if [ -z "$max" ]
then
	max=100
fi

function main(){
start=`date +%s`
if [ $tls == 1 ]
then
	tls=true
else
	tls=false
fi
if [ ! -d asn ]
then
	mkdir asn
fi
if [ ! -f "asn/$asn" ]
then
	echo "正在从ipip.net上下载AS$asn数据"
	curl -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36' -s https://whois.ipip.net/AS$asn | grep /AS$asn/ | awk '{print $2}' | sed -e 's#"##g' | awk -F/ '{print $3"/"$4}' | grep -v :>asn/$asn
	echo "AS$asn数据下载完毕"
else
	echo "AS$asn 已存在,跳过数据下载!"
fi
echo "开始检测 AS$asn TCP端口 $port 有效性"
rm -rf paused.conf ip.txt data.txt
./masscan -p $port -iL asn/$asn --wait=3 --rate=$rate -oL data.txt --interface $Interface
if [ $(grep masscan data.txt | wc -l) == 0 ]
then
	echo "没有TCP端口可用的IP"
else
	grep tcp data.txt | awk '{print $4}' | tr -d '\r'>ip.txt
	echo "开始检测 AS$asn IP有效性"
	./iptest -file=ip.txt -max=$max -outfile=AS$asn-$port.csv -port=$port -speedtest=$speedtest -tls=$tls
fi
end=`date +%s`
rm -rf ip.txt data.txt
echo "AS$asn-$port 总计耗时:$[$end-$start]秒"
}

if [ $scanmode == 2 ]
then
	for i in `cat $filename`
	do
		asn=$(echo $i | awk -F: '{print $1}')
		port=$(echo $i | awk -F: '{print $2}')
		tls=$(echo $i | awk -F: '{print $3}')
		main
	done
else
	main
fi
