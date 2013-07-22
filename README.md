# chem cli

See [chem](http://github.com/superjoe30/chem)

## Usage

```bash
# install dependencies in ubuntu
sudo apt-get install libcairo2-dev

# start with a nearly-empty project, such as a freshly created project
# from github with only a .git/ and README.md.
cd my-project

# init the project with chem-cli
npm install chem-cli
./node_modules/.bin/chem init

# the `dev` command will run a development server which will automatically
# recompile your code, generate your spritesheets, and serve your assets.
# after running `init` above, simply:
npm run dev

# see more commands
./node_modules/.bin/chem
```
    
## Release Notes

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
