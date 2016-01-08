Tweet = require '../models/Tweet' # The Tweet model
CompleteTweets = require '../utils/get-complete-tweets' # Fetches & formats data

# API keys
twitterKey = require('../config/keys').twitter
googlePlacesKey = require('../config/keys').googlePlaces


class FormatTweetsForMap

  # Slightly blur location data, as to not reveal users exact position
  blurLocationData = (loc) ->
    loc = loc + '' # Convert location part into a string
    accuracy = 3 # -1 = 110km, 1 = 10km, 2 = 1km, 3 = 100m, 4 = 10m ...
    digitIndex = (loc).indexOf('.') + accuracy # Find index of digit to modify
    randomDigit = Math.floor(Math.random() * 10)
    if loc.length > digitIndex
      loc = loc.substr(0, digitIndex) + randomDigit + loc.substr(digitIndex + 1)
    Number loc # Convert result back to a number, and return

  # Converts ordinary Tweet array to lat + lng array for the heat map
  formatResultsForMap = (twitterResults) ->
    mapData = []
    for tweet in twitterResults
      if !tweet.location.error?
        mapData.push
          sentiment: tweet.sentiment
          location:
            lat: blurLocationData tweet.location.location.lat
            lng: blurLocationData tweet.location.location.lng
          tweet: tweet.body
    mapData

  # Inserts an array of valid Tweets into the database, if not already
  insertTweetsIntoDatabase = (twitterResults) ->
    for tweet in twitterResults
      tweetData =
        body:     tweet.body
        dateTime: tweet.date
        keywords  : tweet.keywords
        sentiment : tweet.sentiment
        location  : tweet.location
      if isSuitableForDb tweetData
        Tweet.findOneAndUpdate
          body: tweetData.body,
          tweetData,
          upsert: true,
          (err) -> if err then console.log 'ERROR UPDATING TWEET - '+err

  # Determines if a Tweet object is complete & if it should be saved in the db
  isSuitableForDb = (tweetData) ->
    if tweetData.sentiment == 0 then return false
    if tweetData.location.error? then return false
    if !tweetData.location.location.lat? then return false
    if !tweetData.location.location.lng? then return false
    return true

  # Merge two sets of results
  mergeResults = (res1, res2) -> res1.concat res2

  # Make sentence description for map
  makeSentence = (data, searchTerm) ->

    findAv = (arr) ->
      t = 0
      for i in arr then t += i
      t/arr.length

    relatingTo = if searchTerm? then "relating to #{searchTerm}" else ""
    resSource = "the latest Twitter results"

    posSent = []
    negSent = []
    neuSent = []

    for item in data
      if item.sentiment > 0 then posSent.push item.sentiment
      else if item.sentiment < 0 then negSent.push item.sentiment
      else neuSent.push(0)

    avPositive = Math.round(findAv(posSent) * 100)
    avNegative = Math.round(findAv(negSent) * -100)
    avSentiment= Math.round(findAv(posSent.concat(negSent).concat(neuSent))*100)

    overallSentiment =
      if avSentiment > 0 then "Positive"
      else if avSentiment < 0 then "Negative"
      else "Neutral"



    mapShowing = "Map showing #{data.length} of #{resSource} #{relatingTo}<br>"
    mapShowing += "Overall sentiment is: #{overallSentiment} (#{avSentiment}%)"

    sentimentSummary =  "Average positive: #{avPositive}%. "
    sentimentSummary += "Average negative: #{avNegative}%.<br>"

    {
    mapShowing: mapShowing
    sentimentSummary: sentimentSummary
    }


  # Calls methods to fetch and format Tweets from the database
  renderWithDatabaseResults: (cb) ->
    Tweet.getAllTweets (tweets) ->
      cb formatResultsForMap(tweets), makeSentence(tweets, null)

  # Calls methods to fetch fresh Twitter, sentiment, and place data
  renderWithFreshData: (searchTerm, cb) ->
    completeTweets = new CompleteTweets(twitterKey, googlePlacesKey)
    completeTweets.go searchTerm, (webTweets) ->
      insertTweetsIntoDatabase(webTweets) # Add new Tweets to the db
      Tweet.searchTweets searchTerm, (dbTweets) -> # Fetch matching db results
        data = mergeResults webTweets, dbTweets
        cb formatResultsForMap(data), makeSentence(data, searchTerm)

ftfm = new FormatTweetsForMap()
module.exports.getFreshData = ftfm.renderWithFreshData
module.exports.getDbData = ftfm.renderWithDatabaseResults
