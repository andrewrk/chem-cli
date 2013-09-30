# chem cli

See [chem](http://github.com/superjoe30/chem)

## Usage

```bash
# install dependencies in ubuntu
# for other OSes see https://github.com/LearnBoost/node-canvas/wiki/
sudo apt-get install libcairo2-dev

# start with an nearly-empty project such as an empty directory or a
# freshly created project from github with only a .git/ and README.md.
cd my-project

# init the project with chem-cli
npm install chem-cli
./node_modules/.bin/chem init

# the `dev` command will run a development server which will automatically
# recompile your code, generate your spritesheets, and serve your assets.
npm run dev

# see more commands
./node_modules/.bin/chem
```
    
## Release Notes

### 1.2.0

 * asset files can be softlinks
 * dev command takes a --prefix argument so you can put assets in other
   places

### 1.1.0

 * watcher no longer crashes when a syntax error is introduced to the code.
   instead it displays an error message in the browser.
 * avoid some module bloat
 * updated livescript to 1.2.0
 * clean up template html
 * template defaults to adding F5 key to `buttonCaptureExceptions`

### 1.0.11

 * templates have "built with chem" text underneath the game

### 1.0.10

 * always depend on latest chem

### 1.0.9

 * update spritesheet dependency. fixes generated spritesheets not being
   optimally organized

### 1.0.8

 * fix templates

### 1.0.7

 * update chem dependency

### 1.0.6

 * fix not rebuilding spritesheet when source images are changed
 * fix race condition not building bootstrap.js fast enough

### 1.0.5

 * update chem dependency

### 1.0.4
 * ignore files ending in ~
 * update chem dependency

### 1.0.3

 * fix dotfiles making it into asset loading list

### 1.0.2

 * fix dotfiles triggering bootstrap file generation

### 1.0.1

 * update chem dependency

### 1.0.0

 * update to latest browserify
 * start using semver correctly

### 0.6.1

 * add /public/bootstrap.js to auto-generated .gitignore

### 0.6.0

 * add auto generated bootstrap code
 * chemfile.useSpritesheet is automatically set
 * bootstrapping images and text works automatically
 * chem init shows stdout from child process
 * public/img/ and public/text/ are now special dirs
 * fix not noticing certain changes to chemfile
 * still works if directories are missing

### 0.5.2

 * update templates to chem 0.5.0

### 0.5.1

 * fixed #2

### 0.5.0

 * `init` uses current directory instead of creating a project directory

### 0.4.2

 * fixed #1

### 0.4.1

 * `chem init` creates package.json and initializes node_modules
   for you

### 0.4.0

 * Split CLI into this separate package
