#!/usr/bin/env node

var fs = require('fs');
var path = require('path');
var child_process = require('child_process');
var Batch = require('batch');
var chokidar = require('chokidar');
var Vec2d = require('vec2d').Vec2d;
var findit = require('findit');
var ncp = require('ncp').ncp;
var browserify = require('browserify');
var watchify = require('watchify');
var cocoify = require('cocoify');
var icsify = require('icsify');
var liveify = require('liveify');
var coffeeify = require('coffeeify');
var express = require('express');
var noCacheMiddleware = require('connect-nocache')();
var optimist = require('optimist');
var Spritesheet = require('spritesheet');

var clientOut = userPath("./public/main.js");
var imgPath = userPath("./assets/img");
var spritesheetOut = userPath("./public/spritesheet.png");
var animationsJsonOut = userPath("./public/animations.json");
var chemCliPackageJson = require(path.join(__dirname, "package.json"));
var chemPackageJson = require(path.join(path.dirname(require.resolve("chem")), "package.json"));
var objHasOwn = {}.hasOwnProperty;

// allow us to require non-js chemfiles
require('coco');
require('coffee-script');
require('LiveScript');
require('iced-coffee-script');

var allOutFiles = [
  clientOut,
  spritesheetOut,
  animationsJsonOut
];

var tasks = {
  help: cmdHelp,
  init: cmdInit,
  list: cmdList,
  dev: cmdDev,
  clean: cmdClean,
};

run();

function cmdList(args, argv) {
  fs.readdir(path.join(__dirname, "templates"), function(err, files) {
    if (err) {
      console.error("Error reading templates:", err.stack);
      return;
    }
    console.log(files.join("\n"));
  });
}

function cmdInit(args, argv) {
  if (args.length > 0) {
    cmdHelp();
    process.exit(1);
  }
  var projectName = path.basename(path.resolve("."));
  var template = argv.example || "readme";

  var batch = new Batch();
  batch.push(copyTemplate);
  batch.push(installGitIgnore);
  batch.push(initPackageJson);
  batch.end(batchEnd);

  function copyTemplate(cb) {
    var src = chemPath("templates/" + template);
    ncp(src, ".", cb);
  }
  function installGitIgnore(cb) {
    // can't get `npm publish` to accept a file called `.gitignore`,
    // even if it's in a subdirectory, like the template we just copied.
    // see https://github.com/isaacs/npm/issues/1862
    var content = "/node_modules\n" +
      "/public/spritesheet.png\n" +
      "/public/animations.json\n" +
      "/public/main.js\n";
    fs.writeFile(".gitignore", content, cb);
  }
  function initPackageJson(cb) {
    var packageJson = {
      name: projectName,
      version: "0.0.0",
      description: "game prototype using chem game engine",
      scripts: {
        "dev": "npm install && chem dev"
      },
      dependencies: {
        // chem will be installed with npm install --save
        // chem-cli is assumed to already be installed
        "chem-cli": "~" + chemCliPackageJson.version,
      }
    };
    fs.writeFile("package.json", JSON.stringify(packageJson, null, 2), function(err) {
      if (err) return cb(err);
      installChem(cb);
    });
  }
  function installChem(cb) {
    var cmd = ("npm install --save chem@" + chemPackageJson.version).split(" ");
    var child = child_process.spawn(cmd[0], cmd.slice(1));
    child.on('exit', function(code) {
      if (code) cb(new Error("error code " + code + " from: " + cmd.join(" ")));
      cb();
    });
  }
  function batchEnd(err) {
    if (err) {
      console.error("Error setting up:", err.stack);
      return;
    }
    process.stderr.write("Done. Next, try this command:\n\n" +
      "  npm run dev\n");
  }
}

function cmdDev(args, options){
  serveStaticFiles(options.port || 10308);
  compileClientSource({
    watch: true
  });
  watchSpritesheet();
}

function cmdClean() {
  var batch = new Batch();
  allOutFiles.forEach(function(outFile) {
    batch.push(function(done) {
      fs.unlink(outFile, done);
    });
  });
  batch.end(function(err) {
    if (err) {
      console.error("Error deleting files:", err.stack);
    }
  });
}

function cmdHelp(){
  process.stderr.write(
    "Usage: \n\n" +
    "  # create a new project in the current directory\n" +
    "  # project name is assumed to be the name of the current directory\n" +
    "  # `chem list` to see a list of templates to choose from\n\n" +
    "  chem init [--example <template>]\n\n" +
    "  # run a development server which will automatically recompile your code,\n" +
    "  # generate your spritesheets, and serve your assets\n\n" +
    "  chem dev\n\n" +
    "  # delete all generated files\n\n" +
    "  chem clean\n");
}

function run(){
  var argv = optimist.argv;
  var cmd = argv._[0];
  var task = tasks[cmd];
  if (task != null) {
    task(argv._.slice(1), argv);
  } else {
    tasks.help();
  }
}

function extend(obj, src){
  for (var key in src) {
    if (objHasOwn.call(src, key)) {
      obj[key] = src[key];
    }
  }
  return obj;
}

function getChemfilePath (){
  var files = fs.readdirSync(userPath("."));
  for (var i = 0; i < files.length; ++i) {
    var file = files[i];
    if (/^chemfile\./.test(file)) {
      return path.join(userPath("."), file);
    }
  }
  return null;
}

function forceRequireChemfile (){
  var chemPath = path.resolve(getChemfilePath());
  var reqPath = chemPath.substring(0, chemPath.length - path.extname(chemPath).length);
  return forceRequire(reqPath);
}

function chemPath (file){
  return path.join(__dirname, file);
}

function userPath (file){
  return path.join(process.cwd(), file);
}

function compileClientSource (options){
  var chemfile = forceRequireChemfile();
  var compile = options.watch ? watchify : browserify;
  var b = compile(userPath(chemfile.main));
  b.transform(coffeeify);
  //Uncomment when icsify no longer tries to run its filter for .coffee files
  //b.transform(icsify);
  b.transform(liveify);
  b.transform(cocoify);
  if (options.watch) {
    b.on('update', writeBundle);
    writeBundle();
  } else {
    writeBundle();
  }
  function writeBundle() {
    var timestamp = new Date().toLocaleTimeString();
    console.info(timestamp + " - generated " + clientOut);
    b.bundle().pipe(fs.createWriteStream(clientOut));
  }
}

function serveStaticFiles (port){
  var app = express();
  var publicDir = userPath("./public");
  app.use(noCacheMiddleware);
  app.use(express.static(publicDir));
  app.listen(port, function() {
    console.info("Serving at http://0.0.0.0:" + port);
  });
}

function watchSpritesheet (){
  // redo the spritesheet when any files change
  // always compile and watch on first run
  rewatch();
  function recompile(){
    createSpritesheet(function(err, generatedFiles) {
      var timestamp = new Date().toLocaleTimeString();
      if (err) {
        console.info(timestamp + " - " + err.stack);
      } else {
        generatedFiles.forEach(function(file) {
          console.info(timestamp + " - generated " + file);
        });
      }
    });
  }
  function rewatch(){
    // get list of files to watch
    var watchFiles = [getChemfilePath()];
    // get list of all image files
    var animations = forceRequireChemfile().animations;
    getAllImgFiles(function(err, allImgFiles) {
      if (err) {
        console.error("Error getting all image files:", err.stack);
        watchFilesOnce(watchFiles, rewatch);
        return;
      }
      var success = true;
      for (var name in animations) {
        var anim = animations[name];
        var files = filesFromAnimFrames(anim.frames, name, allImgFiles);
        if (files.length === 0) {
          console.error("animation `" + name + "` has no frames");
          success = false;
          continue;
        }
        files.forEach(addWatchFile);
      }
      watchFilesOnce(watchFiles, rewatch);
      if (success) {
        recompile();
      }
    });
    function addWatchFile(file) {
      watchFiles.push(path.join(imgPath, file));
    }
  }
}

function forceRequire (modulePath){
  var resolvedPath = require.resolve(modulePath);
  delete require.cache[resolvedPath];
  return require(modulePath);
}

function cmpStr (a, b){
  if (a < b) {
    return -1;
  } else if (a > b) {
    return 1;
  } else {
    return 0;
  }
}

function getAllImgFiles(cb) {
  var files = [];
  var finder = findit.find(imgPath);
  finder.on('error', cb);
  finder.on('file', function(file) {
    files.push(file);
  });
  finder.on('end', function() {
    cb(null, files);
  });
}

function filesFromAnimFrames (frames, animName, allImgFiles){
  frames = frames || animName;
  if (typeof frames === 'string') {
    var files = allImgFiles.map(function(img){
      return path.relative(imgPath, img);
    }).filter(function(img) {
      return img.indexOf(frames) === 0;
    }).map(function(img) {
      return path.join(imgPath, img);
    });
    files.sort(cmpStr);
    return files;
  } else {
    return frames.map(function(img) {
      return path.join(imgPath, img);
    });
  }
}

function createSpritesheet(cb) {
  var spritesheet = forceRequireChemfile().spritesheet;
  if (spritesheet == null) return [];
  // gather data about all image files
  // and place into array
  var animations = spritesheet.animations;
  var defaults = spritesheet.defaults;
  var sheet = new Spritesheet();
  var abort = false;
  sheet.once('error', function(err) {
    abort = true;
    cb(err);
  });
  getAllImgFiles(function(err, allImgFiles) {
    if (abort) return;
    if (err) return cb(err);
    var anim;
    var seen = {};
    for (var name in animations) {
      anim = animations[name];
      // apply the default animation properties
      animations[name] = anim = extend(extend({}, defaults), anim);
      // change the frames array into an array of objects
      var files = filesFromAnimFrames(anim.frames, name, allImgFiles);
      if (files.length === 0) {
        cb(new Error("animation `" + name + "` has no frames"));
        return;
      }
      anim.frames = [];
      files.forEach(addFile);
    }
    sheet.save(spritesheetOut, function(err) {
      if (abort) return;
      if (err) return cb(err);
      for (var name in animations) {
        var anim = animations[name];
        anim.frames = anim.frames.map(fileToFrame);
        anim.anchor = computeAnchor(anim);
      }
      // render json animation data
      fs.writeFile(animationsJsonOut, JSON.stringify(animations, null, 2), function(err) {
        if (abort) return;
        if (err) return cb(err);
        cb(null, [spritesheetOut, animationsJsonOut]);
      });
    });
    function addFile(file) {
      if (!seen[file]) {
        seen[file] = true;
        sheet.add(file);
      }
      anim.frames.push(file);
    }
  });
  function fileToFrame(file) {
    var sprite = sheet.sprites[file];
    return {
      size: new Vec2d(sprite.image.width, sprite.image.height),
      pos: sprite.pos,
    };
  }
}

function computeAnchor(anim){
  switch (anim.anchor) {
  case 'center':
    return anim.frames[0].size.scaled(0.5).floor();
  case 'topleft':
    return new Vec2d(0, 0);
  case 'topright':
    return new Vec2d(anim.frames[0].size.x, 0);
  case 'bottomleft':
    return new Vec2d(0, anim.frames[0].size.y);
  case 'bottomright':
    return anim.frames[0].size;
  case 'bottom':
    return new Vec2d(anim.frames[0].size.x / 2, anim.frames[0].size.y);
  case 'top':
    return new Vec2d(anim.frames[0].size.x / 2, 0);
  case 'right':
    return new Vec2d(anim.frames[0].size.x, anim.frames[0].size.y / 2);
  case 'left':
    return new Vec2d(0, anim.frames[0].size.y / 2);
  default:
    return anim.anchor
  }
}

function watchFilesOnce(files, cb) {
  var watcher = chokidar.watch(files, {ignored: /^\./, persistent: true});
  watcher.on('change', function() {
    cb();
    watcher.close();
  });
  return watcher;
}
