const quotes = [
    {
        quote: "The only way to do great work is to love what you do.",
        author: "Steve Jobs"
    },
    {
        quote: "Innovation distinguishes between a leader and a follower.",
        author: "Steve Jobs"
    },
    {
        quote: "Stay hungry, stay foolish.",
        author: "Steve Jobs"
    },
    {
        quote: "Your time is limited, don't waste it living someone else's life.",
        author: "Steve Jobs"
    },
    {
        quote: "The future belongs to those who believe in the beauty of their dreams.",
        author: "Eleanor Roosevelt"
    },
    {
        quote: "The best way to predict the future is to create it.",
        author: "Peter Drucker"
    },
    {
        quote: "Strive not to be a success, but rather to be of value.",
        author: "Albert Einstein"
    },
    {
        quote: "The mind is everything. What you think you become.",
        author: "Buddha"
    },
    {
        quote: "Eighty percent of success is showing up.",
        author: "Woody Allen"
    },
    {
        quote: "The only impossible journey is the one you never begin.",
        author: "Tony Robbins"
    }
];

const quoteElement = document.getElementById('quote');
const authorElement = document.getElementById('author');
const newQuoteBtn = document.getElementById('new-quote-btn');

function getRandomQuote() {
    const randomIndex = Math.floor(Math.random() * quotes.length);
    return quotes[randomIndex];
}

function displayQuote() {
    const { quote, author } = getRandomQuote();
    quoteElement.textContent = `"${quote}"`;
    authorElement.textContent = author;
}

newQuoteBtn.addEventListener('click', displayQuote);

// Display an initial quote when the page loads
displayQuote();
