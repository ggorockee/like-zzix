#!/bin/sh
# ML Kit 모델 번들을 앱 루트에 복사한다 (Xcode 빌드 단계 "Copy ML Kit Resources").
#
# SwiftPM 바이너리 타깃은 리소스 번들을 실을 수 없어 앱이 직접 넣어야 하고, 없으면 얼굴·포즈
# 인식기를 처음 쓸 때 앱이 종료된다. 패키지 버전과 항상 맞도록 저장소에 두지 않고 내려받은
# 패키지(google-mlkit-swiftpm)의 예제 폴더에서 복사한다. 못 찾으면 빌드를 실패시킨다.
set -eu

BUNDLES="GoogleMVFaceDetectorResources MLKitPoseDetectionFastResources MLKitPoseDetectionCommonResources MLKitXenoResources"
PACKAGE="checkouts/google-mlkit-swiftpm/Example/Example/Resources/Bundles"

SOURCE=""
for root in \
  "${BUILD_DIR%/Build/*}/SourcePackages" \
  "${SOURCE_ROOT}/../build/ios/SourcePackages" \
  "${BUILD_DIR}/SourcePackages" \
  "${OBJROOT%/Build/*}/SourcePackages"; do
  if [ -d "${root}/${PACKAGE}" ]; then
    SOURCE="${root}/${PACKAGE}"
    break
  fi
done
if [ -z "${SOURCE}" ]; then
  echo "error: google-mlkit-swiftpm 패키지를 찾지 못해 ML Kit 모델을 넣을 수 없습니다 (BUILD_DIR=${BUILD_DIR})"
  exit 1
fi

DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "${DEST}"
for name in ${BUNDLES}; do
  if [ ! -d "${SOURCE}/${name}.bundle" ]; then
    echo "error: ML Kit 모델 번들이 없습니다: ${name}.bundle"
    exit 1
  fi
  rm -rf "${DEST}/${name}.bundle"
  cp -R "${SOURCE}/${name}.bundle" "${DEST}/"
  chmod -R u+w "${DEST}/${name}.bundle"
done
