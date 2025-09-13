# Prosumer-AI-Hackathon
Prosumer AI Hackathon
This project is a full-stack, AI-powered interview coach application. The back end is built using a C# ASP.NET Core Minimal API, while the front end is a single, self-contained HTML file with embedded JavaScript and Tailwind CSS.

Project Description
The application acts as a personal interview practice tool that leverages large language models (LLMs) and text-to-speech technology. Here's how it works:

Interview Questions: The C# back end uses the Anthropic SDK to connect to an AI model (specifically, Claude) and generate realistic interview questions.

Audio Generation: It uses the ElevenLabs SDK to convert the AI-generated questions into natural-sounding speech, which is then streamed directly to the user's browser.

User Interaction: The front-end HTML and JavaScript handle the user interface. It uses the browser's Speech Recognition API to listen to the user's verbal response to the question.

Feedback: Once the user has finished speaking, their transcribed answer is sent back to the C# back end. The back end then prompts the AI model to provide constructive feedback on the answer. This feedback is also converted to audio and played for the user.

In essence, this project provides an interactive and conversational interview practice experience by using powerful AI services to simulate a real-world interview.


