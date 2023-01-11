TERMUX_PKG_HOMEPAGE=https://github.com/microsoft/vscode
TERMUX_PKG_DESCRIPTION="Visual Studio Code"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux-user-repository"
TERMUX_PKG_VERSION="1.74.3"
TERMUX_PKG_SRCURL=git+https://github.com/microsoft/vscode
TERMUX_PKG_GIT_BRANCH="$TERMUX_PKG_VERSION"
TERMUX_PKG_DEPENDS="electron-deps, libx11, libxkbfile, libsecret, ripgrep"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_NO_STATICSPLIT=true
TERMUX_PKG_HOSTBUILD=true
# Chromium doesn't support i686 on Linux.
TERMUX_PKG_BLACKLISTED_ARCHES="i686"
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_TAG_TYPE="latest-release-tag"

termux_step_post_get_source() {
	# Use custom node-native-keymap
	local _native_keymap_verion="$(jq -r '.dependencies."native-keymap"' $TERMUX_PKG_SRCDIR/package.json)"
	local _native_keymap_src_url="https://github.com/microsoft/node-native-keymap/archive/refs/tags/v$_native_keymap_verion.tar.gz"
	local _native_keymap_sha256sum=2db7ee12cf77e76b66f429f7c6e22a9ab6c76a083452dcaa9f11891e410a3795
	local _native_keymap_path="$TERMUX_PKG_CACHEDIR/$(basename $_native_keymap_src_url)"
	termux_download $_native_keymap_src_url $_native_keymap_path $_native_keymap_sha256sum
	tar -xf $_native_keymap_path
	mv node-native-keymap-$_native_keymap_verion node-native-keymap-src
}

termux_step_host_build() {
	if [ -e "$TERMUX_PREFIX/bin" ]; then
		rm -rf $TERMUX_PREFIX/bin.bp
		mv -f $TERMUX_PREFIX/bin $TERMUX_PREFIX/bin.bp
	fi
	termux_setup_nodejs
	npm install yarn
	export PATH="$(npm bin):$PATH"
	if [ -e "$TERMUX_PREFIX/bin.bp" ]; then
		rm -rf $TERMUX_PREFIX/bin
		mv -f $TERMUX_PREFIX/bin.bp $TERMUX_PREFIX/bin
	fi
}

termux_step_configure() {
	termux_setup_nodejs
	export PATH="$TERMUX_PKG_HOSTBUILD_DIR/node_modules/.bin:$PATH"
}

termux_step_make() {
	if [ -e "$TERMUX_PREFIX/bin" ]; then
		rm -rf $TERMUX_PREFIX/bin.bp
		mv -f $TERMUX_PREFIX/bin $TERMUX_PREFIX/bin.bp
	fi

	if [ $TERMUX_ARCH = "arm" ]; then
		export NPM_CONFIG_ARCH=arm
		CODE_ARCH=armhf
		ELECTRON_ARCH=armv7l
	elif [ $TERMUX_ARCH = "x86_64" ]; then
		export NPM_CONFIG_ARCH=x64
		CODE_ARCH=x64
		ELECTRON_ARCH=x64
	elif [ $TERMUX_ARCH = "aarch64" ]; then
		export NPM_CONFIG_ARCH=arm64
		CODE_ARCH=arm64
		ELECTRON_ARCH=arm64
	else
		termux_error_exit "Unsupported arch: $TERMUX_ARCH"
	fi
	export npm_config_arch=$NPM_CONFIG_ARCH

	export CXX="$CXX -v -L$TERMUX_PREFIX/lib"

	yarn
	yarn run gulp vscode-linux-$CODE_ARCH-min

	if [ -e "$TERMUX_PREFIX/bin.bp" ]; then
		rm -rf $TERMUX_PREFIX/bin
		mv -f $TERMUX_PREFIX/bin.bp $TERMUX_PREFIX/bin
	fi
}

termux_step_make_install() {
	mkdir -p $TERMUX_PREFIX/lib/code-oss

	# Download the pre-built electron compiled for Termux
	local _electron_verion="$(jq -r '.devDependencies.electron' $TERMUX_PKG_SRCDIR/package.json)"
	local _electron_archive_url=https://github.com/termux-user-repository/electron-tur-builder/releases/download/v$_electron_verion/electron-v$_electron_verion-linux-$ELECTRON_ARCH.zip
	local _electron_archive_path="$TERMUX_PKG_CACHEDIR/$(basename $_electron_archive_url)"
	termux_download $_electron_archive_url $_electron_archive_path SKIP_CHECKSUM

	# Unzip the pre-built electron
	unzip $_electron_archive_path -d $TERMUX_PREFIX/lib/code-oss

	# Rename the binary file
	mv $TERMUX_PREFIX/lib/code-oss/electron $TERMUX_PREFIX/lib/code-oss/code-oss

	# Remove the default resources
	rm -rf $TERMUX_PREFIX/lib/code-oss/resources/*

	# Copy resources
	cp -r --no-preserve=ownership --preserve=mode ../VSCode-linux-$CODE_ARCH/resources/* $TERMUX_PREFIX/lib/code-oss/resources/

	# Install the start script
	mkdir -p $TERMUX_PREFIX/lib/code-oss/bin
	cp ../VSCode-linux-$CODE_ARCH/bin/code-oss $TERMUX_PREFIX/lib/code-oss/bin/code-oss
	sed -i "s|/usr/bin|$TERMUX_PREFIX/bin|g
			s|/usr/share/code-oss|$TERMUX_PREFIX/lib/code-oss|g
			s|/proc/version|/dev/null|g" $TERMUX_PREFIX/lib/code-oss/bin/code-oss
	chmod +x $TERMUX_PREFIX/lib/code-oss/bin/code-oss

	# Replace ripgrep
	ln -sfr $TERMUX_PREFIX/bin/rg $TERMUX_PREFIX/lib/code-oss/resources/app/node_modules.asar.unpacked/@vscode/ripgrep/bin/rg

	# Install appdata and desktop file
	sed -i "s|@@NAME_SHORT@@|Code|g
			s|@@NAME_LONG@@|Code - OSS|g
			s|@@NAME@@|code-oss|g
			s|@@ICON@@|com.visualstudio.code.oss|g
			s|@@EXEC@@|$TERMUX_PREFIX/bin/code-oss|g
			s|@@LICENSE@@|MIT|g" resources/linux/code{.appdata.xml,-workspace.xml,.desktop,-url-handler.desktop}
	install -Dm600 resources/linux/code.appdata.xml $TERMUX_PREFIX/share/metainfo/code-oss.appdata.xml
	install -Dm600 resources/linux/code-workspace.xml $TERMUX_PREFIX/share/mime/packages/code-oss.workspace.xml
	install -Dm600 resources/linux/code.desktop $TERMUX_PREFIX/share/applications/code-oss.desktop
	install -Dm600 resources/linux/code-url-handler.desktop $TERMUX_PREFIX/share/applications/code-oss-url-handler.desktop
	install -Dm600 ../VSCode-linux-$CODE_ARCH/resources/app/resources/linux/code.png $TERMUX_PREFIX/share/pixmaps/com.visualstudio.code.oss.png

	# Install binaries to $PREFIX/bin
	ln -sfr $TERMUX_PREFIX/lib/code-oss/bin/code-oss $TERMUX_PREFIX/bin/code-oss
	ln -sfr $TERMUX_PREFIX/bin/code-oss $TERMUX_PREFIX/bin/code
	ln -sfr $TERMUX_PREFIX/bin/code-oss $TERMUX_PREFIX/bin/vscode

	# Install shell completions
	cp resources/completions/bash/code resources/completions/bash/code-oss
	cp resources/completions/bash/code resources/completions/bash/vscode
	cp resources/completions/zsh/_code resources/completions/zsh/_code-oss
	cp resources/completions/zsh/_code resources/completions/zsh/_vscode
	sed -i 's|@@APPNAME@@|code|g' resources/completions/{bash/code,zsh/_code}
	sed -i 's|@@APPNAME@@|vscode|g' resources/completions/{bash/vscode,zsh/_vscode}
	sed -i 's|@@APPNAME@@|code-oss|g' resources/completions/{bash/code-oss,zsh/_code-oss}
	install -Dm600 resources/completions/bash/code $TERMUX_PREFIX/share/bash-completion/completions/code
	install -Dm600 resources/completions/zsh/_code $TERMUX_PREFIX/share/zsh/site-functions/_code
	install -Dm600 resources/completions/bash/vscode $TERMUX_PREFIX/share/bash-completion/completions/vscode
	install -Dm600 resources/completions/zsh/_vscode $TERMUX_PREFIX/share/zsh/site-functions/_vscode
	install -Dm600 resources/completions/bash/code-oss $TERMUX_PREFIX/share/bash-completion/completions/code-oss
	install -Dm600 resources/completions/zsh/_code-oss $TERMUX_PREFIX/share/zsh/site-functions/_code-oss

	# Install license files
	mkdir -p $TERMUX_PREFIX/share/doc/code-oss
	cp ../VSCode-linux-$CODE_ARCH/resources/app/LICENSE.txt $TERMUX_PREFIX/share/doc/code-oss/LICENSE
	cp ../VSCode-linux-$CODE_ARCH/resources/app/ThirdPartyNotices.txt $TERMUX_PREFIX/share/doc/code-oss/ThirdPartyNotices.txt
}