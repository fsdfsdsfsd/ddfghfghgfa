    fs = require 'fs'
    path = require 'path'
    handlebars = require 'handlebars'
    aws = require 'aws-sdk'
    shortid = require 'shortid'
    Hashids = require 'hashids'
    hashids = new Hashids(process.env["AWS_ACCESS_KEY"])


Grab our environment variables...

    DOMAIN = process.env["DOMAIN"] || "thelee.ch"
    BUCKET = process.env["BUCKET"] || DOMAIN
    GA_ID = process.env["GA_ID"]
    PARTITION = process.env["PARTITION"] || false

Setup the connection to s3

    aws.config.update {
        accessKeyId: process.env["AWS_ACCESS_KEY"],
        secretAccessKey: process.env["AWS_SECRET_KEY"]
    }
    aws.config.region = 'us-east-1'
    s3 = new aws.S3()

Make sure the S3 bucket is setup as a website. We'll just do this each time we 
start the app. This means that it will frequently fail, but it's the simplest
way to make sure that we've setup the bucket correctly.

    s3.createBucket { Bucket: DOMAIN, ACL: "public-read" }, (err, data) ->
      if err
        console.log "[ERROR]: #{err}"
      else
        welcome = fs.readFileSync path.join(__dirname, "welcome-ascii.txt")
        welcome = "<pre>#{welcome}</pre>"
        params = {
          Bucket: BUCKET
          Key: "index.html",
          ACL: "public-read",
          Body: welcome,
          ContentType: "text/html"
        }
        s3.putObject params, (err, data) ->
          if err
            console.log "[ERROR]: error creating index.html #{err}"
            return
          params = {
            Bucket: BUCKET,
            WebsiteConfiguration: {
              IndexDocument: {
                Suffix: 'index.html'
              }
            }
          }
          s3.putBucketWebsite params, (err, data) ->
            if err
              console.log "[ERROR]: #{err}"

--------
We're going to make `leech` (this module) exportable so that we can use it in
the app, as a command line tool, and as it's own funciton. It takes 1 argument
(the url) which makes it easy to plug-n-play in other stuff.

    module.exports = (url, fn) ->

This is our basic HTML template that we'll use for doing the redirect. It's just
going to send the user to another page as soon as it's loaded. There's no server
since it's just a static file, but everything will be tracked by GA.

      source = """
      <html>
          <title>{{url}}</title>
          <body>
          <script>
            <!-- Google Analytics -->
              (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
              (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
              m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
              })(window,document,'script','//www.google-analytics.com/analytics.js','ga');

              ga('create', '{{ga_id}}', 'auto');
              ga('send', 'pageview');
              // redirect
              window.location.replace('{{url}}');
            </script>
          </body>
      </html>
      """

      template = handlebars.compile(source)

Data should just be the user's Google Analytics Id and the URL that they want to
minify.

      data = { url: url, ga_id: GA_ID }
      html = template(data)

We're going to generate a shortlink for the URL. [`shortid`](https://github.com/dylang/shortid)
does a pretty good job at balancing between being short, and also being unique! 
We'll take that `_id` and turn it into the key for an S3 object. If you want 
this to be really "scalable", you can "hash" your S3 keys. All this means is 
that you split the key into 2 parts like so: ("abcd123" --> "abc/d123"). S3 will
automatically partition you keys across more servers and will dramatically 
increase preformance.

      shortid.characters "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ()"
      _id = shortid.generate()
      if PARTITION
        _id = _id.slice(0, 3) + "/" + _id.slice(3)
      params = {
        Bucket: BUCKET,
        Key: _id
        ACL: "public-read",
        Body: html,
        ContentType: "text/html",
        Metadata: {
          url: url
        }
      }
      s3.putObject params, (err, data) ->
          if err
            console.log err
          fn err, path.join(DOMAIN, _id)

