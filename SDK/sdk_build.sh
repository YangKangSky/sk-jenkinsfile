#!/bin/sh

###setup env
export PATH=$HOME/user_bin:$PATH
workdir=$(pwd)
echo "workdir:$workdir"
#code_root_dir=$workdir
code_root_dir=$workdir/WORKDIR
mkdir -p $code_root_dir
echo "code_root_dir:$code_root_dir"
cd $code_root_dir

export LANG=en_US.UTF-8

export GIT_SSL_NO_VERIFY=1

RELEASE_VERSION="default"


# 异常处理函数
function handle_error {
  echo "Error: Command or function failed with exit code $?" >&2
  exit 1
}

# 捕获所有非零返回值的命令和函数
trap handle_error ERR


evn_prepare() {
	cd ${code_root_dir}
	if [ ! -d $code_root_dir/downloads ];then
		echo "ln -sf  /home/jenkins/workspace/rdk_downloads $code_root_dir/downloads"
        ln -sf  /home/jenkins/workspace/rdk_downloads $code_root_dir/downloads
	fi
	
	echo "MANIFEST=${MANIFEST}" 
	echo "BRANCH=${BRANCH}"
	echo "MACHINE_NAME=${MACHINE_NAME}" 
	echo "TARGET_IMAGE=${TARGET_IMAGE}" 
	echo "BUILD_PARAM=${BUILD_PARAM}" 
	echo "REPOURL=${REPOURL}" 
	echo "USE_SSTATE_CACHE=${USE_SSTATE_CACHE}" 
	echo "DISTRO_FEATURES=${DISTRO_FEATURES}" 
	echo "PATCHLIST=${PATCHLIST}"
	cd -	
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
	cd ${code_root_dir}
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
	cd -
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
	echo "cleanall done"
}


sync_project() {
	cd ${code_root_dir}
	echo "Starting repo init: repo init -u $REPOURL -b $BRANCH -m $MANIFEST"
	echo $PATH
	export PATH=$HOME/bin:$PATH

	repo init -u $REPOURL -b $BRANCH -m $MANIFEST
	repo sync -j 32
	echo "default repo sync completed"
    
    git clone "ssh://gerrit01.sdt.com:29418/RDK/meta-skyworth-licenses"
    echo "meta-skyworth-licenses sync completed"
	cd -
}




build_project() {
	cd ${code_root_dir}
	echo "Starting bitbake build"
	export LOCAL_BUILD=1

    
	source meta-skyworth-licenses/setup-environment $MACHINE_NAME

	echo "add DISTRO_FEATURES_append = \" ${DISTRO_FEATURES} \""
	echo "DISTRO_FEATURES_append = \" ${DISTRO_FEATURES} \"  ">>conf/local.conf 

    # remove the limit of build resources
    sed -i '/BB_NUMBER_THREADS = "4"\|PARALLEL_MAKE = "-j 4"/d' conf/local.conf 

	echo "bitbake $TARGET_IMAGE"
	#bitbake $TARGET_IMAGE
	cd -
}


version_record() {
    MACHINE_TYPE=$(ls -1 ${BUILDDIR}/tmp/deploy/images/)
    BUILD_DIR=$(dirname ${BUILDDIR})
    BUILD_DIR_BASE=$(basename ${BUILDDIR})
    BUILD_DIR=${BUILD_DIR}/${BUILD_DIR_BASE}

	rm -rf ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
    
	cd ${code_root_dir}
    echo "meta layers version info:" > ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
	repo info >>  ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
    cd -
	
	cd ${BUILDDIR}/
    echo "recipe source version info:" >> ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
    buildhistory-collect-srcrevs -a >>  ${BUILD_DIR}/tmp/deploy/images/${MACHINE_TYPE}/project_version.txt
	cd -
}

bspinfo_get() {
  # 从auto.conf文件获取RDKM_MANIFEST_DATETIME和RELEASE_VERSION的值
  cd ${BUILDDIR}/
  RDKM_MANIFEST_DATETIME=$(grep -oP 'RDKM_MANIFEST_DATETIME\s*=\s*"\K[^"]+' ${BUILDDIR}/conf/auto.conf)
  RELEASE_VERSION=$(grep -oP 'RELEASE_VERSION\s*=\s*"\K[^"]+' ${BUILDDIR}/conf/auto.conf)
  
  echo "RDKM_MANIFEST_DATETIME: $RDKM_MANIFEST_DATETIME"
  echo "RELEASE_VERSION: $RELEASE_VERSION"
  echo "MACHINE_NAME: $MACHINE_NAME"
  cd -
}


upload_image() {
	###upload image
	case ${MACHINE_NAME} in
		mesonsc2-5.4-lib32-ah212)
			release_tarball=amlogic_ah212_${RELEASE_VERSION}_image_`date +%Y%m%d%H%M`.zip
			ftp_board_path=ah212
			;;
		*)
			echo "Please Select Valid BOARD_TYPE:${MACHINE_NAME} !"
			exit 1
			;;
	esac	

	###upload image
	if [ -f ${BUILDDIR}/tmp/deploy/images/meson*/aml_upgrade_package.img ]; then
      cd ${BUILDDIR}/tmp/deploy/images/meson*
      zip -qrv $release_tarball aml_upgrade_package.img  project_version.txt *-u-boot.aml.zip  u-boot.bin.signed 
      mkdir -p /home/jenkins/workspace/311_image/rdk/nightly/${ftp_board_path}
      #upload to 192.168.3.11
      cp $release_tarball /home/jenkins/workspace/311_image/rdk/nightly/${ftp_board_path} -f
      echo "The image file will be located at \\\192.168.3.11\Jenkins_image\rdk\nightly\\${ftp_board_path}\\${release_tarball}"

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
    #cleanall
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

function upload() {
	bspinfo_get
	upload_image
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
		echo "prepare done..."
		;;
	"sync")
		echo "sync..."
		sync
		echo "sync done..."
		;;
	"build")
		echo "build..."
		build
		echo "build done..."
		;;
	"upload")
		echo "upload..."
		upload
		echo "upload done..."
		;;
	*)
		echo "invalid choice"
		;;
	esac
}

main $1

exit 0
















