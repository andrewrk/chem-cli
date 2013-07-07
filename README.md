# chem cli

See [chem](http://github.com/superjoe30/chem)

## Usage

    # install dependencies in ubuntu
    sudo apt-get install libcairo2-dev

    # start with a nearly-empty project,
    # such as a freshly created project from github with only a .git/ and README.md.
    cd my-project

    # init the project with chem-cli
    npm install chem-cli
    ./node_modules/.bin/chem init

    # the `dev` command will run a development server which will automatically recompile your code,
    # generate your spritesheets, and serve your assets.
    # after running `init` above, simply:
    npm run dev

    # see more commands
    ./node_modules/.bin/chem
    
## Release Notes

### 0.4.2

 * fixed #1

### 0.4.1

 * `chem init` creates package.json and initializes node_modules
   for you

### 0.4.0

 * Split CLI into this separate package
