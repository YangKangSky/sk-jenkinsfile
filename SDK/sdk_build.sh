#!/bin/bash

###setup env
export PATH=$HOME/user_bin:$PATH
workdir=$(pwd)
echo "workdir:$workdir"
#code_root_dir=$workdir
code_root_dir=$workdir
mkdir -p $code_root_dir
echo "code_root_dir:$code_root_dir"
cd $code_root_dir

export LANG=en_US.UTF-8

export GIT_SSL_NO_VERIFY=1


params_list=("$@")

for param in "${params[@]}"
do
  echo "Parameter is: $param" 
done


# 异常处理函数
function handle_error {
  echo "Error: Command or function failed with exit code $?" >&2
  exit 1
}

# 捕获所有非零返回值的命令和函数
trap handle_error ERR


evn_prepare() {
	if [ ! -d $code_root_dir/downloads ];then
		echo "ln -sf  /home/jenkins/workspace/rdk_downloads $code_root_dir/downloads"
        ln -sf  /home/jenkins/workspace/rdk_downloads $code_root_dir/downloads
	fi
}

patch_for_hdcp() {
	echo "patch_for_hdcp"
}
patch_for_netflix() {
	echo "patch_for_netflix"
    DISTRO_FEATURES="${DISTRO_FEATURES} netflix-prebuilt-pkg "
}

patch_for_amazon() {
	echo "patch_for_amazon"
	cd $code_root_dir/.repo/manifests
	git fetch https://code.rdkcentral.com/r/collaboration/soc/amlogic/aml-accel-manifests refs/changes/18/92218/1 && git cherry-pick FETCH_HEAD
	cd $code_root_dir
	repo sync -j8
	DISTRO_FEATURES="${DISTRO_FEATURES} amazon-plugin "
}

patch_for_youtube() {
	echo "patch_for_amazon"
	echo "patch_for_netflix"
    DISTRO_FEATURES="${DISTRO_FEATURES} youtube-prebuilt-pkg "
}

patch_for_bootloader() {
	echo "patch_for_bootloader"
}
patch_for_dolbyvision() {
	echo "patch_for_dolbyvision"
    DISTRO_FEATURES="${DISTRO_FEATURES} sk-dolby-vision "
}
patch_for_dolbyms12() {
	echo "patch_for_dolbyms12"
}

apply_patch() {
	echo "PATCHLIST is $PATCHLIST"
    #PATCHLIST="HDCP,NETFLIX,AMAZON,BOOTLOADER,DOLBYVISION,DOLBYMS12"
    IFS=',' read -ra PATCHES <<< "$PATCHLIST"
    for patch in "${PATCHES[@]}"; do
      case "$patch" in
        "HDCP")
          echo -e "patch HDCP\n"
          patch_for_hdcp
          ;;
        "NETFLIX")
          echo -e "patch NETFLIX\n"
          patch_for_netflix
          ;;
        "AMAZON")
          echo -e "patch AMAZON\n"
          patch_for_amazon
          ;;
        "YOUTUBE")
          echo -e "patch Youtube\n"
          patch_for_youtube
          ;;   
        "BOOTLOADER")
          echo -e "patch BOOTLOADER\n"
          patch_for_bootloader
          ;;
        "DOLBYVISION")
          echo -e "patch DOLBYVISION\n"
          patch_for_dolbyvision
          ;;
        "DOLBYMS12")
          echo -e "patch DOLBYMS12\n"
          patch_for_dolbyms12
          ;;
        *)
          echo ""
          ;;
      esac
    done
}

cleanall () {
    echo "cleanall all cache"
	rm -rf $code_root_dir/build*
	rm -rf $code_root_dir/meta*
	rm -rf $code_root_dir/poky
	rm -rf $code_root_dir/sstate-cache
	#rm -rf ./.repo
	rm -rf $code_root_dir/.repo/manifests .repo/manifests.git 
	rm -rf $code_root_dir/.templateconf
	rm -rf $code_root_dir/docs
	rm -rf $code_root_dir/openembedded-core
}


sync_project() {
	echo "Starting repo init: repo init -u $REPOURL -b $BRANCH -m $MANIFEST"
	echo $PATH
	export PATH=$HOME/bin:$PATH

	repo init -u $REPOURL -b $BRANCH -m $MANIFEST
	repo sync -j 32
	echo "default repo sync completed"
    
    git clone "ssh://gerrit01.sdt.com:29418/RDK/meta-skyworth-licenses"
    echo "meta-skyworth-licenses sync completed"
}




build_project() {
	echo "Starting bitbake build"
	export LOCAL_BUILD=1

    
	source meta-skyworth-licenses/setup-environment $MACHINE_NAME

	echo "add DISTRO_FEATURES_append = \" ${DISTRO_FEATURES} \""
	echo "DISTRO_FEATURES_append = \" ${DISTRO_FEATURES} \"  ">>conf/local.conf 

    # remove the limit of build resources
    sed -i '/BB_NUMBER_THREADS = "4"\|PARALLEL_MAKE = "-j 4"/d' conf/local.conf 

	echo "bitbake $TARGET_IMAGE"
	bitbake $TARGET_IMAGE
}


version_record() {
    MACHINE_TYPE=$(ls -1 ${code_root_dir}/build/tmp/deploy/images/)
    BUILD_DIR=$(dirname ${code_root_dir}/build)
    BUILD_DIR_BASE=$(basename ${code_root_dir}/build)
    BUILD_DIR=${BUILD_DIR}/${BUILD_DIR_BASE}

	rm -rf ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
    
    echo "meta layers version info:" > ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
	repo info >>  ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
    
    echo "recipe source version info:" >> ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
    buildhistory-collect-srcrevs -a >>  ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
}

bspinfo_get() {
  # 从auto.conf文件获取RDKM_MANIFEST_DATETIME和RELEASE_VERSION的值
  cd ${code_root_dir}/build
  RDKM_MANIFEST_DATETIME=$(grep -oP 'RDKM_MANIFEST_DATETIME\s*=\s*"\K[^"]+' auto.conf)
  RELEASE_VERSION=$(grep -oP 'RELEASE_VERSION\s*=\s*"\K[^"]+' auto.conf)
  
  echo "RDKM_MANIFEST_DATETIME: $RDKM_MANIFEST_DATETIME"
  echo "RELEASE_VERSION: $RELEASE_VERSION"
  echo "MACHINE_NAME: $MACHINE_NAME"
  cd -
  
}


upload_image() {
	###upload image
	case ${BOARD_TYPE} in
		HY44Q)
			release_tarball=fetchtv_hy44q_image_`date +%Y%m%d%H%M`.zip
			;;
		*)
			echo "Please Select Valid BOARD_TYPE:${BOARD_TYPE} !"
			exit 1
			;;
	esac	
	
	#HY44Q
	ftp_board_path=${BOARD_TYPE}_inner
	###upload image
	if [ -f tmp/deploy/images/meson*/aml_upgrade_package_ab_dr.img ]; then
      cd tmp/deploy/images/meson*
      zip -qrv $release_tarball aml_upgrade_package_ab_dr.img aml_upgrade_package_ab_dr_signed.img  project_version.txt *-u-boot.aml.zip rootfs-debug.tar.gz u-boot.bin.signed u-boot.bin.device.signed recovery.img boot.img rootfs.squashfs  dtb.img logo.img
      mkdir -p /home/jenkins/workspace/311_image/rdk_fetchtv/nightly/${ftp_board_path}
      #upload to 192.168.3.11
      cp $release_tarball /home/jenkins/workspace/311_image/rdk_fetchtv/nightly/${ftp_board_path} -f
      echo "The image file will be located at \\\192.168.3.11\Jenkins_image\rdk_fetchtv\nightly\\${ftp_board_path}\\${release_tarball}"

      #upload to 192.168.203.67	
      curl -T $release_tarball ftp://192.168.203.67/Jenkins_image/RDK_platform/${ftp_board_path}/ --user OST:abc.123
      echo "The image file will be located at \\\192.168.203.67\Jenkins_image\RDK_platform\image\\${ftp_board_path}\\${release_tarball}"
      rm -rf $release_tarball	  
      
      
      rm -rf $release_tarball
      echo "The whole process is complete!"
      exit 0
    else
      echo "The build is failed!"
      exit 1
    fi
}






function prepare() {
	#环境准备
	evn_prepare

	#remove build and meta files
    cleanall
}

function sync() {
    #sync the project 
    sync_project
}

function build() {
    #apply the patch by parameters
    apply_patch
    
	#build the project 
	build_project

    #record the meta layer and recipe source version
    version_record
	
}


main() {

	#upload the image to ftp server
	#upload_image
    
	#remove build and meta files
    #cleanall
	
	action=$1
	
	case $action in
	"prepare")
		echo "prepare..."
		prepare
		;;
	"sync")
		echo "sync..."
		sync
		;;
	"build")
		echo "build..."
		build
		;;
	*)
		echo "invalid choice"
		;;
	esac
}

main $1
















