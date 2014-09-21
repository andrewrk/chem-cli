#!/usr/bin/env node

var fs = require('fs');
var path = require('path');
var spawn = require('spawn-cmd').spawn;
var Pend = require('pend');
var chokidar = require('chokidar');
var findit = require('findit');
var ncp = require('ncp').ncp;
var watchify = require('watchify');
var browserify = require('browserify');
var cocoify = require('cocoify');
var liveify = require('liveify');
var coffeeify = require('coffeeify');
var connect = require('connect');
var serveStatic = require('serve-static');
var http = require('http');
var noCacheMiddleware = require('connect-nocache')();
var optimist = require('optimist');
var Spritesheet = require('spritesheet');

var clientOut = userPath("./public/main.js");
// spritesheet source
var imgPath = userPath("./assets/img");
// static resources
var publicDir = userPath("./public");
var textPath = userPath("./public/text");
var staticImgPath = userPath("./public/img");
var spritesheetOut = userPath("./public/spritesheet.png");
var animationsJsonOut = userPath("./public/animations.json");
var bootstrapJsOut = userPath("./public/bootstrap.js");
var chemCliPackageJson = require(path.join(__dirname, "package.json"));
var objHasOwn = {}.hasOwnProperty;

// allow us to require non-js chemfiles
require('coco');
require('coffee-script');
require('LiveScript');

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

// set this to a string to cause the http server to send
// an error message instead of anything else
var bundleSyntaxError = null;

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

  var pend = new Pend();
  pend.go(copyTemplate);
  pend.go(installGitIgnore);
  pend.go(initPackageJson);
  pend.wait(printMessageAndDone);

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
      "/public/bootstrap.js\n" +
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
    var options = {
      stdio: 'inherit',
    };
    var child = spawn('npm', [
        'install', '--save', 'chem'], options);
    child.on('error', cb);
    child.on('exit', function(code) {
      if (code) {
        cb(new Error("error code " + code));
        return;
      }
      cb();
    });
  }
  function printMessageAndDone(err) {
    if (err) {
      console.error("Error setting up:", err.stack);
      return;
    }
    process.stderr.write("Done. Next, try this command:\n\n" +
      "  npm run dev\n");
  }
}

function cmdDev(args, options){
  var firstTime = true;
  serveStaticFiles(options.port || 10308);
  watchBootstrap(options.prefix, onGeneratedBootstrap);
  watchSpritesheet();
  function onGeneratedBootstrap() {
    if (! firstTime) return;
    firstTime = false;
    compileClientSource({
      watch: true
    });
  }
}

function cmdClean() {
  var pend = new Pend();
  allOutFiles.forEach(function(outFile) {
    pend.go(function(cb) {
      fs.unlink(outFile, cb);
    });
  });
  pend.wait(function(err) {
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
  var w = null;

  rewatch();

  function rewatch() {
    if (w != null) {
      w.close();
      w = null;
    }
    watchFilesOnce([getChemfilePath()], rewatch);
    var chemfile = forceRequireChemfile();

    var b = browserify({
      cache: {},
      packageCache: {},
      fullPaths: true,
    });
    b.add(userPath(chemfile.main));

    if (chemfile.autoBootstrap !== false) {
      b.add(bootstrapJsOut);
    }
    b.transform(coffeeify);
    b.transform(liveify);
    b.transform(cocoify);
    if (options.watch) {
      w = watchify(b);
      w.on('update', writeBundle);
      writeBundle();
    } else {
      writeBundle();
    }
    function writeBundle() {
      var bundleStream = b.bundle();
      bundleStream.on('error', function(err) {
        bundleSyntaxError = err.message;
        var timestamp = new Date().toLocaleTimeString();
        console.info(timestamp + " - error " + bundleSyntaxError);
      });
      var outStream = fs.createWriteStream(clientOut);
      outStream.on('close', function() {
        bundleSyntaxError = null;
        var timestamp = new Date().toLocaleTimeString();
        console.info(timestamp + " - generated " + clientOut);
      });
      bundleStream.pipe(outStream);
    }
  }
}

function watchBootstrap(prefix, generatedEventFn) {
  // this function must generate bootstrapJsOut once and every time
  // the chemfile updates.
  // cb is called every time bootstrap is generated
  rewatch();
  function recompile() {
    generateBootstrapJs(prefix, function(err) {
      var timestamp = new Date().toLocaleTimeString();
      if (err) {
        console.info(timestamp + " - " + err.stack);
      } else {
        console.info(timestamp + " - generated " + bootstrapJsOut);
      }
      generatedEventFn();
    });
  }
  function rewatch() {
    // list of files to watch
    var watchFiles = [getChemfilePath()];
    var watchDirs = [textPath, staticImgPath];
    watchFilesAndDirsOnce(watchFiles, watchDirs, rewatch);
    recompile();
  }
}

function generateBootstrapJs(prefix, cb) {
  var chemfile = forceRequireChemfile();
  if (chemfile.autoBootstrap === false) {
    fs.unlink(bootstrapJsOut, function(err) {
      if (err && err.code === 'ENOENT') {
        cb();
      } else {
        cb(err);
      }
    });
    return;
  }
  var pend = new Pend();
  var allTextFiles, allStaticImgFiles;
  pend.go(function(cb) {
    getAllTextFiles(function(err, _allTextFiles) {
      allTextFiles = _allTextFiles;
      cb(err);
    });
  });
  pend.go(function(cb) {
    getAllStaticImageFiles(function(err, _allStaticImgFiles) {
      allStaticImgFiles = _allStaticImgFiles;
      cb(err);
    });
  });
  pend.wait(function(err) {
    if (err) return cb(err);

    var textObj = {};
    var textCount = 0;
    allTextFiles.forEach(function(textFile) {
      var name = path.relative(textPath, textFile);
      textObj[name] = path.relative(publicDir, textFile);
      textCount += 1;
    });

    var imgObj = {};
    var imgCount = 0;
    allStaticImgFiles.forEach(function(imgFile) {
      var name = path.relative(staticImgPath, imgFile);
      imgObj[name] = path.relative(publicDir, imgFile);
      imgCount += 1;
    });

    var code = "// This code is auto-generated based on your chemfile.\n";
    code += "// `exports.autoBootstrap = false` to disable this file.\n";
    code += "var chem = require('chem');\n";
    if (!chemfile.spritesheet) {
      code += "chem.resources.useSpritesheet = false;\n";
    }
    var json;
    if (textCount >= 1) {
      json = JSON.stringify(textObj, null, 2);
      code += "chem.resources.text = " + json + ";\n";
    }
    if (imgCount >= 1) {
      json = JSON.stringify(imgObj, null, 2);
      code += "chem.resources.images = " + json + ";\n";
    }
    if (prefix) {
      code += "chem.resources.prefix = " + JSON.stringify(prefix) + ";\n";
    }
    code += "chem.resources.bootstrap();\n";
    fs.writeFile(bootstrapJsOut, code, cb);
  });
}

function serveStaticFiles (port){
  var app = connect();
  app.use(noCacheMiddleware);
  app.use(errorMsgMiddleware);
  app.use(serveStatic(publicDir));
  var server = http.createServer(app);
  server.listen(port, function() {
    console.info("Serving at http://0.0.0.0:" + port + "/");
  });
}

function errorMsgMiddleware(req, resp, next) {
  if (!bundleSyntaxError) return next();

  resp.setHeader('Content-Type', "text/plain");
  resp.end(bundleSyntaxError);
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
    var spritesheet = forceRequireChemfile().spritesheet;
    if (spritesheet == null) {
      watchFilesOnce(watchFiles, rewatch);
      recompile();
    } else {
      addAllImgFilesToWatch();
    }
    function addWatchFile(file) {
      watchFiles.push(file);
    }
    function addAllImgFilesToWatch() {
      getAllImgFiles(function(err, allImgFiles) {
        if (err) {
          console.error("Error getting all image files:", err.stack);
          watchFilesOnce(watchFiles, rewatch);
          return;
        }
        var success = true;
        for (var name in spritesheet.animations) {
          var anim = spritesheet.animations[name];
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

function getAllTextFiles(cb) {
  getAllFiles(textPath, cb);
}

function getAllFiles(dir, cb) {
  var files = [];
  var finder = findit(dir);
  finder.on('file', onFileOrLink);
  finder.on('link', onFileOrLink);

  finder.on('end', function() {
    cb(null, files);
  });


  function onFileOrLink(file) {
    if (! isDotFile(file)) {
      files.push(file);
    }
  }
}

function getAllImgFiles(cb) {
  getAllFiles(imgPath, cb);
}

function getAllStaticImageFiles(cb) {
  getAllFiles(staticImgPath, cb);
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
      size: xy(sprite.image.width, sprite.image.height),
      pos: sprite.pos,
    };
  }
}

function computeAnchor(anim){
  switch (anim.anchor) {
  case 'center':
    return xy(Math.floor(anim.frames[0].size.x / 2),
        Math.floor(anim.frames[0].size.y / 2));
  case 'topleft':
    return xy(0, 0);
  case 'topright':
    return xy(anim.frames[0].size.x, 0);
  case 'bottomleft':
    return xy(0, anim.frames[0].size.y);
  case 'bottomright':
    return anim.frames[0].size;
  case 'bottom':
    return xy(Math.floor(anim.frames[0].size.x / 2), anim.frames[0].size.y);
  case 'top':
    return xy(Math.floor(anim.frames[0].size.x / 2), 0);
  case 'right':
    return xy(anim.frames[0].size.x, Math.floor(anim.frames[0].size.y / 2));
  case 'left':
    return xy(0, Math.floor(anim.frames[0].size.y / 2));
  default:
    return anim.anchor
  }
}

function isDotFile(fullPath) {
  var basename = path.basename(fullPath);
  return (/^\./).test(basename) || (/~$/).test(basename);
}

function watchFilesAndDirsOnce(files, dirs, cb) {
  var opts = {
    ignored: isDotFile,
    persistent: true,
    ignoreInitial: true,
  };

  var fileWatcher = chokidar.watch(files, opts);
  fileWatcher.on('change', itHappened);
  fileWatcher.on('error', onError);

  var dirWatcher = chokidar.watch(dirs, opts);
  dirWatcher.on('add', itHappened);
  dirWatcher.on('unlink', itHappened);
  fileWatcher.on('error', onError);

  function itHappened() {
    fileWatcher.close();
    dirWatcher.close();
    cb();
  }

  function onError(err) {
    console.error("Error watching files:", err.stack);
  }
}

function watchFilesOnce(files, cb) {
  watchFilesAndDirsOnce(files, [], cb);
}

function xy(x, y) {
  return {x: x, y: y};
}
