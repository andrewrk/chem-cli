# chem cli

See [chem](https://github.com/andrewrk/chem)

## Usage

```bash
# install dependencies in ubuntu
# for other OSes see https://github.com/LearnBoost/node-canvas/wiki/
sudo apt-get install libcairo2-dev libgif-dev

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
