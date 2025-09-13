// This C# file is a self-contained ASP.NET Core Minimal API.
// It serves a single HTML page and provides API endpoints for the coach functionality.

// You will need to install the following NuGet packages:
// dotnet add package Anthropic.SDK
// dotnet add package ElevenLabs-DotNet

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Configuration;
using System.Text;
using System.IO;
using System.Threading.Tasks;
using Anthropic.SDK;
using Anthropic.SDK.Messaging;
using ElevenLabs;
using System.Net.Http;

// Configure the web application builder
var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddHttpClient();
builder.Services.AddSingleton<AnthropicClient>(sp =>
{
    var apiKey = sp.GetRequiredService<IConfiguration>()["ANTHROPIC_API_KEY"];
    return new AnthropicClient(apiKey);
});
builder.Services.AddSingleton<ElevenLabsClient>(sp =>
{
    var apiKey = sp.GetRequiredService<IConfiguration>()["ELEVENLABS_API_KEY"];
    return new ElevenLabsClient(apiKey);
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}

app.UseRouting();

// Endpoint to serve the HTML/JS frontend
app.MapGet("/", async context =>
{
    var htmlContent = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>AI Interview Coach</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
            @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700&display=swap');
            body { font-family: 'Inter', sans-serif; background-color: #f3f4f6; }
            .container { max-width: 800px; }
            .btn { transition: all 0.2s; }
            .btn:hover { transform: translateY(-2px); box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06); }
            #loading-indicator { display: none; }
        </style>
    </head>
    <body class="bg-gray-100 flex items-center justify-center min-h-screen p-4">
        <div class="container bg-white rounded-lg shadow-xl p-8 space-y-6 flex flex-col items-center">
            <h1 class="text-3xl font-bold text-gray-800 text-center">Your AI Interview Coach</h1>
            <p class="text-gray-500 text-center">Click "Start" to begin. The coach will ask you a question. Speak your answer, and then click "Get Feedback".</p>
            <button id="startButton" class="btn bg-green-500 text-white font-semibold py-3 px-6 rounded-full shadow-lg hover:bg-green-600 focus:outline-none focus:ring-4 focus:ring-green-500 focus:ring-opacity-50">
                Start Interview
            </button>
            <div id="loading-indicator" class="text-gray-500 font-semibold flex items-center space-x-2">
                <svg class="animate-spin h-5 w-5 text-gray-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <span>Loading...</span>
            </div>
            <div id="coach-message" class="w-full text-center p-4 bg-gray-200 rounded-lg text-gray-700 font-medium">
                Click "Start" to begin.
            </div>
            <div class="w-full space-y-4" id="controls" style="display: none;">
                <div class="flex items-center space-x-4">
                    <button id="recordButton" class="btn w-full bg-blue-500 text-white font-semibold py-3 px-6 rounded-full shadow-lg hover:bg-blue-600 focus:outline-none focus:ring-4 focus:ring-blue-500 focus:ring-opacity-50">
                        Speak Your Answer
                    </button>
                    <button id="feedbackButton" class="btn w-full bg-indigo-500 text-white font-semibold py-3 px-6 rounded-full shadow-lg hover:bg-indigo-600 focus:outline-none focus:ring-4 focus:ring-indigo-500 focus:ring-opacity-50">
                        Get Feedback
                    </button>
                </div>
                <div id="user-response-box" class="w-full p-4 bg-white border border-gray-300 rounded-lg shadow-inner">
                    <h3 class="font-semibold text-gray-700">Your Response:</h3>
                    <p id="user-response" class="text-gray-600 mt-2 italic">Waiting for you to speak...</p>
                </div>
                <button id="nextQuestionButton" class="btn w-full bg-gray-500 text-white font-semibold py-3 px-6 rounded-full shadow-lg hover:bg-gray-600 focus:outline-none focus:ring-4 focus:ring-gray-500 focus:ring-opacity-50">
                    Next Question
                </button>
            </div>
        </div>
    
        <script>
            // State management
            let currentQuestion = "";
            let userResponseText = "";
            const audioContext = new (window.AudioContext || window.webkitAudioContext)();
            const speechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
            let recognition = null;
    
            // DOM elements
            const startButton = document.getElementById('startButton');
            const recordButton = document.getElementById('recordButton');
            const feedbackButton = document.getElementById('feedbackButton');
            const nextQuestionButton = document.getElementById('nextQuestionButton');
            const coachMessageEl = document.getElementById('coach-message');
            const userResponseEl = document.getElementById('user-response');
            const controlsEl = document.getElementById('controls');
            const loadingIndicator = document.getElementById('loading-indicator');
            
            // Helper functions
            function setLoading(isLoading) {
                loadingIndicator.style.display = isLoading ? 'flex' : 'none';
                startButton.disabled = isLoading;
                recordButton.disabled = isLoading;
                feedbackButton.disabled = isLoading;
                nextQuestionButton.disabled = isLoading;
            }

            async function playAudio(url) {
                const response = await fetch(url);
                const arrayBuffer = await response.arrayBuffer();
                const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
                const source = audioContext.createBufferSource();
                source.buffer = audioBuffer;
                source.connect(audioContext.destination);
                source.start();
            }

            // API calls
            async function getQuestion() {
                setLoading(true);
                try {
                    const response = await fetch('/api/question');
                    const data = await response.json();
                    currentQuestion = data.question;
                    coachMessageEl.textContent = currentQuestion;
                    userResponseEl.textContent = "Waiting for you to speak...";
                    await playAudio(`/api/audio?text=${encodeURIComponent(currentQuestion)}`);
                } catch (error) {
                    console.error("Failed to fetch question:", error);
                    coachMessageEl.textContent = "Error: Could not get question.";
                } finally {
                    setLoading(false);
                }
            }

            async function getFeedback() {
                if (!userResponseText) {
                    coachMessageEl.textContent = "Please speak your answer first.";
                    return;
                }
                setLoading(true);
                try {
                    const response = await fetch('/api/feedback', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            question: currentQuestion,
                            answer: userResponseText
                        })
                    });
                    const data = await response.json();
                    const feedback = data.feedback;
                    coachMessageEl.textContent = feedback;
                    await playAudio(`/api/audio?text=${encodeURIComponent(feedback)}`);
                } catch (error) {
                    console.error("Failed to get feedback:", error);
                    coachMessageEl.textContent = "Error: Could not get feedback.";
                } finally {
                    setLoading(false);
                }
            }
            
            // Event listeners
            startButton.addEventListener('click', () => {
                startButton.style.display = 'none';
                controlsEl.style.display = 'block';
                coachMessageEl.textContent = "Loading...";
                getQuestion();
            });

            recordButton.addEventListener('click', () => {
                if (!speechRecognition) {
                    coachMessageEl.textContent = "Speech Recognition is not supported by your browser. Please use Chrome or Firefox.";
                    return;
                }
                if (recognition) {
                    recognition.stop();
                    recognition = null;
                }

                recognition = new speechRecognition();
                recognition.interimResults = false;
                recognition.lang = 'en-US';
                recognition.continuous = false;

                recognition.onstart = () => {
                    userResponseEl.textContent = "Listening... Speak now!";
                    recordButton.textContent = "Recording...";
                    recordButton.disabled = true;
                };

                recognition.onresult = (event) => {
                    const result = event.results[event.results.length - 1][0].transcript;
                    userResponseText = result;
                    userResponseEl.textContent = result;
                };

                recognition.onend = () => {
                    recordButton.textContent = "Speak Your Answer";
                    recordButton.disabled = false;
                    coachMessageEl.textContent = "Click 'Get Feedback' to continue.";
                };

                recognition.onerror = (event) => {
                    console.error('Speech recognition error:', event);
                    userResponseEl.textContent = `Error: ${event.error}`;
                    recordButton.textContent = "Speak Your Answer";
                    recordButton.disabled = false;
                    coachMessageEl.textContent = "Error during recording. Try again.";
                };

                recognition.start();
            });

            feedbackButton.addEventListener('click', getFeedback);
            nextQuestionButton.addEventListener('click', getQuestion);
        </script>
    </body>
    </html>
    """;
    context.Response.ContentType = "text/html";
    await context.Response.WriteAsync(htmlContent);
});

// Endpoint to get a new interview question from Anthropic Claude
app.MapGet("/api/question", async (AnthropicClient claudeClient) =>
{
    var questionPrompt = "You are an AI interviewer. Provide a single, common behavioral or technical interview question. The question should be concise, around 1-2 sentences. Do not include any greetings or salutations.";
    var message = new MessageParam("user", new List<ContentBase>() { new TextContent(questionPrompt) });

    var response = await claudeClient.Messages.CreateAsync(new MessageParameters()
    {
        Messages = new List<MessageParam>() { message },
        Model = Anthropic.SDK.Constants.Claude3Sonnet,
        MaxTokens = 100
    });

    var question = response.Content[0].Text;
    return Results.Ok(new { question = question });
});

// Endpoint to get feedback on an answer from Anthropic Claude
app.MapPost("/api/feedback", async (HttpContext context, AnthropicClient claudeClient) =>
{
    var body = await context.Request.ReadFromJsonAsync<dynamic>();
    string question = body.question;
    string answer = body.answer;

    var feedbackPrompt = $"You are an expert interview coach. I will give you an interview question and a candidate's answer. Provide concise, constructive feedback on the answer in a single short paragraph. Focus on clarity, directness, and potential improvements. Do not include any greetings or salutations. \n\nQuestion: '{question}'\nAnswer: '{answer}'";
    var message = new MessageParam("user", new List<ContentBase>() { new TextContent(feedbackPrompt) });

    var response = await claudeClient.Messages.CreateAsync(new MessageParameters()
    {
        Messages = new List<MessageParam>() { message },
        Model = Anthropic.SDK.Constants.Claude3Sonnet,
        MaxTokens = 200
    });

    var feedback = response.Content[0].Text;
    return Results.Ok(new { feedback = feedback });
});

// Endpoint to generate audio from ElevenLabs and stream it back
app.MapGet("/api/audio", async (HttpContext context, ElevenLabsClient elevenLabsClient, string text) =>
{
    context.Response.ContentType = "audio/mpeg";
    var audioStream = await elevenLabsClient.TextToSpeechEndpoint.StreamAsync(text, "YOUR_CHOSEN_VOICE_ID_HERE");
    await audioStream.CopyToAsync(context.Response.Body);
});

app.Run();
